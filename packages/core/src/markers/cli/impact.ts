// `impact` command core (0.2.0 F2). ADVISORY, READ-ONLY change-impact lens.
//
// Question answered: "which bound behaviours does my current change touch, so I
// know what to re-verify?" It cross-references the git diff (changed files +
// changed line ranges) against the MATERIALIZED bindings the freshness engine
// sees, and classifies each binding:
//
//   IMPACTED        the binding's file changed AND a changed hunk overlaps its
//                   span  -> re-verify (high signal)
//   TOUCHED         the binding's file changed but no hunk overlaps its span
//                   -> probably fine (informational)
//   BROKEN_BINDING  the binding's file was DELETED or RENAMED away -> the marked
//                   code moved/gone; the binding likely needs re-binding
//
// It NEVER derives or changes a freshness/trust verdict, NEVER mints/voids
// evidence, and NEVER writes a ledger. It reuses `prepareScan` purely to READ the
// materialized bindings (identical to what verify/prove/scan see), and the same
// injectable `GitRunner` the append-only check uses for all git access.
import type { ResolvedWorkspaceContext } from "../../roots.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import type { PublicKeyResolver } from "../proofSignature.js";
import type { GitRunner } from "../appendOnly.js";
import { readBaseRefFile } from "../appendOnly.js";
import { scanFiles } from "../scanner.js";
import {
  collectChangedFiles,
  rangesOverlap,
  type ChangedFile,
  type LineRange
} from "../gitDiff.js";
import { nodeMarkerFs, type MarkerFs } from "./io.js";
import { prepareScan } from "./scan.js";

// The schema id of the impact report envelope's data payload.
export const IMPACT_REPORT_SCHEMA_ID = "ucase-impact-report-v1";

// One materialized binding whose file changed with an overlapping hunk.
export interface ImpactedBinding {
  row_id: string;
  binding_slug: string;
  file: string;
  span: LineRange;
  overlapping_ranges: LineRange[];
}

// One materialized binding whose file changed but whose span no hunk overlaps.
export interface TouchedBinding {
  row_id: string;
  binding_slug: string;
  file: string;
  span: LineRange;
}

// One materialized binding whose file was deleted or renamed away.
export interface BrokenBinding {
  row_id: string;
  binding_slug: string;
  file: string; // the file the marker used to live in (the base-ref path)
  reason: "deleted" | "renamed";
}

export interface ImpactCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  publicKeyResolver: PublicKeyResolver;
  generatedAt: string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
  gitRunner?: GitRunner;
  // The repo the git diff runs in (defaults to productRoot).
  repoCwd?: string;
  // Comparison mode (mirrors the CLI flags). base wins the ref; staged uses the
  // index; default is the working tree vs HEAD.
  base?: string;
  staged?: boolean;
}

export interface ImpactCommandResult {
  schema: typeof IMPACT_REPORT_SCHEMA_ID;
  exit_code: number;
  ok: boolean;
  command: "impact";
  base: string;
  changed_files: ChangedFile[];
  impacted: ImpactedBinding[];
  touched: TouchedBinding[];
  broken_bindings: BrokenBinding[];
  summary: string;
  errors: Array<{ code: string; message: string }>;
}

function fail(partial: Partial<ImpactCommandResult> & { exit_code: number }): ImpactCommandResult {
  return {
    schema: IMPACT_REPORT_SCHEMA_ID,
    command: "impact",
    ok: partial.exit_code === 0,
    base: partial.base ?? "HEAD",
    changed_files: partial.changed_files ?? [],
    impacted: partial.impacted ?? [],
    touched: partial.touched ?? [],
    broken_bindings: partial.broken_bindings ?? [],
    summary: partial.summary ?? "",
    errors: partial.errors ?? [],
    ...partial
  };
}

// A materialized (registered + present) binding, flattened from the freshness
// status rows: exactly the bindings verify/prove would target, with their
// current file + span.
interface MaterializedBinding {
  row_id: string;
  binding_slug: string;
  file: string;
  span: LineRange;
}

// A registered binding whose marker is ABSENT from the current scan (the
// freshness engine reports it under `missing_registered_binding_slugs`). These
// are the BROKEN_BINDING candidates once we confirm a delete/rename.
interface MissingBinding {
  row_id: string;
  binding_slug: string;
}

// Build a lowercase, order-stable summary line for humans.
function buildSummary(
  impacted: number,
  touched: number,
  broken: number
): string {
  const parts: string[] = [];
  parts.push(`${impacted} behaviour${impacted === 1 ? "" : "s"} impacted`);
  if (touched > 0) {
    parts.push(`${touched} touched`);
  }
  if (broken > 0) {
    parts.push(`${broken} binding${broken === 1 ? "" : "s"} broken by your changes`);
  }
  return parts.join(", ");
}

export function runImpactCommand(options: ImpactCommandOptions): ImpactCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const repoCwd = options.repoCwd ?? options.productRoot;
  const runner = options.gitRunner;

  // READ-ONLY reuse of the freshness pipeline: we only consume the materialized
  // binding view; we never write anything derived from it, and we do not pass a
  // base ref here (impact's own git access is separate from the append-only
  // check).
  const prepared = prepareScan({
    context: options.context,
    productRoot: options.productRoot,
    bindingsPath: options.bindingsPath,
    evidencePath: options.evidencePath,
    policyMode: "feature",
    publicKeyResolver: options.publicKeyResolver,
    generatedAt: options.generatedAt,
    fs,
    commentConfig: options.commentConfig,
    repoCwd: options.repoCwd
  });

  // Present, registered bindings (row.current_bindings is C(row) ∩ present),
  // plus registered-but-missing slugs (the broken-binding candidates).
  const materialized: MaterializedBinding[] = [];
  const missing: MissingBinding[] = [];
  for (const row of prepared.status.rows) {
    for (const binding of row.current_bindings) {
      materialized.push({
        row_id: row.row_id,
        binding_slug: binding.binding_slug,
        file: binding.file_path,
        span: { start_line: binding.span_start_line, end_line: binding.span_end_line }
      });
    }
    for (const slug of row.missing_registered_binding_slugs) {
      missing.push({ row_id: row.row_id, binding_slug: slug });
    }
  }

  // Collect the diff. A missing base ref / not-a-git-repo surfaces as a thrown
  // git error; the CLI layer maps it to the right exit code, so here we let it
  // propagate as a coded failure.
  let diff;
  try {
    diff = collectChangedFiles({
      runner,
      cwd: repoCwd,
      base: options.base,
      staged: options.staged
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return fail({
      exit_code: 1,
      errors: [{ code: "GIT_DIFF_FAILED", message }]
    });
  }

  // Index the changed files for O(1) lookup. Renames and deletes are tracked by
  // their OLD path (where the marked code used to live) so a binding whose file
  // moved/vanished is detected against the path the scan/registry knew.
  const changedByCurrentPath = new Map<string, ChangedFile>();
  const removedOldPaths = new Map<string, "deleted" | "renamed">();
  // Rename DESTINATIONS: a `git mv` carries the marker to the new path, so the
  // scan still finds the binding (it is NOT missing) — but the marked code MOVED,
  // which the spec treats as a broken binding (its registered location changed).
  const renamedDestPaths = new Set<string>();
  for (const file of diff.files) {
    changedByCurrentPath.set(file.file, file);
    if (file.change === "deleted") {
      removedOldPaths.set(file.file, "deleted");
    } else if (file.change === "renamed" && file.old_file) {
      removedOldPaths.set(file.old_file, "renamed");
      renamedDestPaths.add(file.file);
    }
  }

  // Classify present bindings: BROKEN (its file is a rename destination — the
  // marked code moved), else IMPACTED (span overlaps a hunk) or TOUCHED (file
  // changed, no overlap).
  const impacted: ImpactedBinding[] = [];
  const touched: TouchedBinding[] = [];
  const brokenFromPresent: BrokenBinding[] = [];
  for (const binding of materialized) {
    if (renamedDestPaths.has(binding.file)) {
      brokenFromPresent.push({
        row_id: binding.row_id,
        binding_slug: binding.binding_slug,
        file: binding.file,
        reason: "renamed"
      });
      continue;
    }
    const changed = changedByCurrentPath.get(binding.file);
    if (!changed || changed.change === "deleted") {
      continue; // file unchanged -> not in this change's blast radius
    }
    const overlapping = changed.ranges.filter((range) => rangesOverlap(binding.span, range));
    if (overlapping.length > 0) {
      impacted.push({
        row_id: binding.row_id,
        binding_slug: binding.binding_slug,
        file: binding.file,
        span: binding.span,
        overlapping_ranges: overlapping
      });
    } else {
      touched.push({
        row_id: binding.row_id,
        binding_slug: binding.binding_slug,
        file: binding.file,
        span: binding.span
      });
    }
  }

  // Classify BROKEN bindings: a registered slug whose marker vanished BECAUSE its
  // file was deleted or renamed away. We resolve the (now-gone) marker's file by
  // scanning the base-ref content of each removed path and matching the slug — so
  // a broken binding reports the exact file the marked code used to live in.
  const brokenFromMissing = classifyBrokenBindings({
    missing,
    removedOldPaths,
    showRef: showRefFor(options),
    repoCwd,
    runner,
    commentConfig: options.commentConfig
  });
  // A present binding on a rename destination + a missing binding whose base-ref
  // marker was on a removed path are disjoint (the same slug cannot be both
  // present and missing), so concatenation cannot double-count.
  const broken = [...brokenFromPresent, ...brokenFromMissing];

  const summary = buildSummary(impacted.length, touched.length, broken.length);

  // Advisory: exit 0 in the normal case regardless of how much is impacted. Real
  // errors (bad ref / not a git repo) are handled above / at the CLI layer.
  return fail({
    exit_code: 0,
    base: diff.base,
    changed_files: diff.files,
    impacted,
    touched,
    broken_bindings: broken,
    summary
  });
}

// The ref to `git show` the OLD (pre-change) content from: the base ref when
// comparing against one, else HEAD (both the working-tree and --staged modes
// compare against HEAD).
function showRefFor(options: ImpactCommandOptions): string {
  return options.base ?? "HEAD";
}

interface ClassifyBrokenOptions {
  missing: MissingBinding[];
  removedOldPaths: Map<string, "deleted" | "renamed">;
  showRef: string;
  repoCwd: string;
  runner?: GitRunner;
  commentConfig?: CommentPrefixConfig;
}

function classifyBrokenBindings(options: ClassifyBrokenOptions): BrokenBinding[] {
  if (options.missing.length === 0 || options.removedOldPaths.size === 0) {
    return [];
  }
  // Which registered slugs are still missing to be accounted for.
  const missingBySlug = new Map<string, MissingBinding>();
  for (const item of options.missing) {
    missingBySlug.set(item.binding_slug, item);
  }

  const broken: BrokenBinding[] = [];
  // Scan the base-ref content of each removed path; any marker whose slug is in
  // the missing set is a broken binding, attributed to that path's change reason.
  for (const [oldPath, reason] of options.removedOldPaths) {
    if (missingBySlug.size === 0) {
      break;
    }
    let baseText: string;
    try {
      baseText = readBaseRefFile(options.showRef, oldPath, {
        cwd: options.repoCwd,
        runner: options.runner
      });
    } catch {
      continue; // unreadable base content: cannot attribute; skip (best-effort)
    }
    if (baseText === "") {
      continue;
    }
    const scan = scanFiles([{ file_path: oldPath, contents: baseText }], {
      config: options.commentConfig
    });
    for (const binding of scan.bindings) {
      const match = missingBySlug.get(binding.binding_slug);
      if (!match) {
        continue;
      }
      broken.push({
        row_id: match.row_id,
        binding_slug: binding.binding_slug,
        file: oldPath,
        reason
      });
      missingBySlug.delete(binding.binding_slug);
    }
  }
  return broken;
}
