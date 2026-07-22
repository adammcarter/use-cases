// Shared inputs for the Phase 7 CLI command cores.
//
// Loads marker "rows" from the existing use-case YAML loader (REUSING
// loadUseCaseMatrix rather than a parallel parser), walks product source for
// marker-bearing files, and resolves trusted-CI public keys. Everything here is
// deterministic given its inputs; clocks/ids/verification are injected by callers.
import { isAbsolute, join, relative } from "node:path";
import type { ResolvedWorkspaceContext } from "../../roots.js";
import { loadUseCaseMatrix } from "../../useCases/loadUseCaseMatrix.js";
import type { MatrixSnapshot } from "../../useCases/types.js";
import type { FreshnessInputRow } from "../freshness.js";
import type { PemOrKeyObject, PublicKeyResolver } from "../proofSignature.js";
import {
  resolveCommentPrefix,
  type CommentPrefixConfig
} from "../commentPrefix.js";
import type { CurrentBindingRecord, ScanInput } from "../scanner.js";
import { nodeMarkerFs, type MarkerFs } from "./io.js";

// A loaded marker row: the use-case object with a `row_id` alias plus its two
// policies forced to a non-undefined value so the policy hashes never throw on a
// row that omits them. The whole object feeds computeRowHash, so bind/scan/prove
// MUST build it identically — that is exactly why it lives in one place.
export interface LoadedMarkerRows {
  rows: FreshnessInputRow[];
  rowIds: Set<string>;
  snapshot: MatrixSnapshot;
}

export function loadMarkerRows(context: ResolvedWorkspaceContext): LoadedMarkerRows {
  const snapshot = loadUseCaseMatrix({ context });
  // A variant FAMILY stays ONE row here: the marker slug (and therefore the row id)
  // is the family, and its `variants` ride along on the row as parameters. Variant
  // fan-out (one spawn + one result record per variant) happens in verify, and the
  // per-variant status breakdown in scan — both read the `variants` list off the row.
  // Keeping the family as the row means binding, the slug grammar, and the freshness
  // derivation stay unchanged; variants never need a slug the grammar forbids.
  const rows: FreshnessInputRow[] = snapshot.addressableUseCases.map((useCase) => {
    const value = useCase.value as Record<string, unknown>;
    return {
      ...value,
      row_id: useCase.value.id,
      verification_policy: value.verification_policy ?? null,
      approval_policy: value.approval_policy ?? null
    };
  });
  return { rows, rowIds: new Set(rows.map((row) => row.row_id)), snapshot };
}

// The declared variants of a family row, in stable key order (or [] for an ordinary
// row). The single source verify and scan both use to fan a family into its variants.
export function rowVariants(row: FreshnessInputRow): Array<{ key: string; title?: string }> {
  const variants = (row as { variants?: unknown }).variants;
  if (!Array.isArray(variants)) {
    return [];
  }
  return [...(variants as Array<{ key: string; title?: string }>)].sort((left, right) =>
    left.key < right.key ? -1 : left.key > right.key ? 1 : 0
  );
}

export function findRow(rows: ReadonlyArray<FreshnessInputRow>, rowId: string): FreshnessInputRow | undefined {
  return rows.find((row) => row.row_id === rowId);
}

// Directory names never walked for markers: VCS/deps, the data dir itself, and
// common build-output dirs. Build output (e.g. tsc's dist/) can carry COPIES of
// a marker comment from source, which would otherwise read as a duplicate slug.
const DEFAULT_SKIP_DIRS = new Set([
  ".git",
  // Agent/session state — notably .claude/worktrees holds full repo COPIES whose
  // source markers would otherwise read as duplicate slugs and poison the scan.
  ".claude",
  "node_modules",
  ".use-cases",
  "dist",
  "dist-ts",
  "build",
  "out",
  "coverage",
  ".next",
  ".turbo",
  ".svelte-kit"
]);

// A directory carrying its own workspace config IS its own workspace: its markers
// name ITS rows, so reading them from the parent reports them as ROW_NOT_FOUND.
// This subsumes the old hardcoded `examples` skip — that was one instance of the
// rule — and covers test fixtures and vendored sample apps, which hit the same
// wall. The nested workspace's own `scan --repo <dir>` is unaffected, since that
// config sits at ITS product root rather than below it.
//: @use-case:lifecycle.signals.nested_workspace_is_not_scanned
const WORKSPACE_CONFIG_FILES = ["use-cases.yml", "use-cases.yaml"];

function isNestedWorkspace(fs: MarkerFs, dir: string): boolean {
  return WORKSPACE_CONFIG_FILES.some((name) => fs.readText(join(dir, name)) !== null);
}
//: @use-case:end lifecycle.signals.nested_workspace_is_not_scanned

export interface CollectSourceOptions {
  fs?: MarkerFs;
  config?: CommentPrefixConfig;
  // Absolute paths whose subtrees are skipped (e.g. the resolved data_root).
  skipPaths?: string[];
}

// Walk the product root and read every file that has a configured comment prefix
// (so the scanner only sees files that could legally carry a marker). Returns
// ScanInput records keyed by a posix path relative to productRoot, so binding
// records and span hashes are stable regardless of where the repo lives on disk.
export function collectSourceInputs(productRoot: string, options: CollectSourceOptions = {}): ScanInput[] {
  const fs = options.fs ?? nodeMarkerFs;
  const skip = new Set((options.skipPaths ?? []).map((path) => path));
  const inputs: ScanInput[] = [];

  const walk = (dir: string): void => {
    let entries;
    try {
      entries = fs.listDir(dir);
    } catch {
      return;
    }
    for (const entry of entries) {
      if (entry.isSymlink) {
        continue; // never follow symlinks
      }
      const full = join(dir, entry.name);
      if (entry.isDirectory) {
        if (DEFAULT_SKIP_DIRS.has(entry.name) || skip.has(full)) {
          continue;
        }
        // Checked on the child, never the product root itself — otherwise the
        // repo's own config would skip the entire scan.
        if (isNestedWorkspace(fs, full)) {
          continue;
        }
        walk(full);
        continue;
      }
      if (!entry.isFile) {
        continue;
      }
      const relPath = toPosix(relative(productRoot, full));
      const contents = fs.readText(full);
      if (contents === null) {
        continue;
      }
      // Resolve with contents so extensionless shebang scripts (e.g.
      // hooks/session-start) are recognised, not silently skipped.
      if (resolveCommentPrefix(relPath, options.config, contents) === null) {
        continue; // no configured prefix => cannot carry a marker
      }
      inputs.push({ file_path: relPath, contents });
    }
  };

  walk(productRoot);
  inputs.sort((left, right) => (left.file_path < right.file_path ? -1 : left.file_path > right.file_path ? 1 : 0));
  return inputs;
}

export function toPosix(path: string): string {
  return path.split("\\").join("/");
}

export function resolveUnderRoot(root: string, value: string): string {
  return isAbsolute(value) ? value : join(root, value);
}

// Build a PublicKeyResolver from a single trusted public key. Because v1 trusts
// exactly one key file, any key_id resolves to it (a tampered signature still
// fails BAD_SIGNATURE; an unknown alg still fails before resolution). Callers that
// need strict key_id matching can pass `keyId`.
export function singleKeyResolver(publicKey: PemOrKeyObject, keyId?: string): PublicKeyResolver {
  return (requestedKeyId: string) => {
    if (keyId !== undefined && requestedKeyId !== keyId) {
      return undefined;
    }
    return publicKey;
  };
}

// Recompute the current, registered binding records for one row from a scan,
// filtered to the slugs the registry actually knows (spec 7: C(row)).
export function registeredBindingsForRow(
  bindings: ReadonlyArray<CurrentBindingRecord>,
  rowId: string,
  registeredSlugs: ReadonlySet<string>
): CurrentBindingRecord[] {
  return bindings.filter(
    (binding) => binding.row_id === rowId && registeredSlugs.has(binding.binding_slug)
  );
}
