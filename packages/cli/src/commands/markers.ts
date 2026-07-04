// The "markers" command group: bind / scan / prove / verify / validate-ledger.
// This is the security core — the FRESH proof path — so every handler is a
// byte-for-byte port of the legacy run* functions: identical core calls,
// identical arguments (including new Date().toISOString() defaults, repoCwd, the
// GitHub-shaped producer block, and the CI authority), identical createCliResult
// shapes, and identical exit codes on every path. The local legacy helpers
// (markerPaths / markerPublicKeyResolver / markerSigningKey / generateUlid) are
// ported in VERBATIM; emitMarkerResult becomes a non-writing helper that returns
// { envelope, exitCode } instead of writing stdout.
import { readFileSync } from "node:fs";
import { createPrivateKey, createPublicKey } from "node:crypto";
import { join, resolve } from "node:path";
import type { CiAuthority, VerificationResultRecord } from "@adammcarter/use-cases-core";
import type { CliCommand, CommandOutput, ParsedFlags } from "../command/types.js";
import {
  createCliResult,
  detectCiAuthority,
  errorEnvelope,
  keyringPublicKeyResolverFromFile,
  resolveContextOrError,
  runBindCommand,
  runImpactCommand,
  runProveCommand,
  runScanCommand,
  runValidateLedgerCommand,
  runVerifyCommand,
  singleKeyResolver,
  type ResolvedContext
} from "../runtime.js";
import { loadUcmCore } from "../coreLoader.js";
import { workspaceFlags } from "./common.js";

// getVersionInfo is not re-exported by runtime.ts, and a static import of core
// from a command module would bypass the diagnostics.contracts.missing_build_hint
// friendly fallback (see legacy.ts). Reach it through the SAME cached loadUcmCore
// path every other module uses, so the missing-build hint stays intact.
const { getVersionInfo } = await loadUcmCore();

// --- ported legacy helpers (made non-writing where they emitted output) -------

// Verbatim port of the legacy `markerPaths`: resolve the product root and the
// bindings/evidence ledger paths from flags, defaulting to the workspace root and
// the .use-cases ledgers under the data root.
function markerPaths(flags: ParsedFlags, context: ResolvedContext) {
  const productRoot = (flags.productRoot as string | undefined)
    ? resolve(process.cwd(), flags.productRoot as string)
    : context.workspace_root;
  const bindingsPath = (flags.bindings as string | undefined)
    ? resolve(process.cwd(), flags.bindings as string)
    : join(context.data_root, ".use-cases", "bindings.jsonl");
  const evidencePath = (flags.proofs as string | undefined)
    ? resolve(process.cwd(), flags.proofs as string)
    : join(context.data_root, ".use-cases", "proofs.jsonl");
  return { productRoot, bindingsPath, evidencePath };
}

// A malformed key would otherwise surface as a raw OpenSSL DECODER exception with
// an empty stdout. Turn it into a clean coded error that the dispatcher renders as
// the standard ok:false envelope, and point the user at the key-management doc.
function keyMaterialError(kind: "signing" | "public", origin: string, cause: unknown): Error {
  const detail = cause instanceof Error ? cause.message : String(cause);
  const error = new Error(
    `The ${kind} key (${origin}) is not a valid PEM key — expected a PKCS8 ed25519 PEM. ` +
      `See docs/security/key-management.md to generate one. (${detail})`
  );
  (error as { code?: string }).code = kind === "signing" ? "signing_key.invalid" : "public_key.invalid";
  return error;
}

// Verbatim port of the legacy `markerPublicKeyResolver`.
function markerPublicKeyResolver(flags: ParsedFlags): ReturnType<typeof singleKeyResolver> {
  // Opt-in multi-key path: --keyring builds a resolver that enforces per-key
  // status (active/revoked) and validity windows against the proof's created_at.
  // When both flags are present the keyring wins over the single --public-key.
  const keyringPath = flags.keyring as string | undefined;
  if (keyringPath) {
    return keyringPublicKeyResolverFromFile(resolve(process.cwd(), keyringPath));
  }
  const keyPath = flags.publicKey as string | undefined;
  if (!keyPath) {
    // No configured key: any proof signature fails (ledger with proofs is invalid).
    return () => undefined;
  }
  const pem = readFileSync(resolve(process.cwd(), keyPath), "utf8");
  try {
    return singleKeyResolver(createPublicKey(pem));
  } catch (error) {
    throw keyMaterialError("public", keyPath, error);
  }
}

// Verbatim port of the legacy `markerSigningKey`.
function markerSigningKey(flags: ParsedFlags): { privateKey: ReturnType<typeof createPrivateKey>; keyId: string } | undefined {
  const envName = flags.signingKeyEnv as string | undefined;
  if (!envName) {
    return undefined;
  }
  const pem = process.env[envName];
  if (!pem) {
    return undefined;
  }
  try {
    return { privateKey: createPrivateKey(pem), keyId: (flags.keyId as string | undefined) ?? "trusted-ci" };
  } catch (error) {
    throw keyMaterialError("signing", `$${envName}`, error);
  }
}

// Minimal ULID-shaped id for registry/proof event ids (uniqueness from the tail).
// Verbatim port of the legacy `generateUlid`.
function generateUlid(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  const time = Date.now().toString(32).toUpperCase().padStart(10, "0").slice(0, 10);
  let tail = "";
  for (let i = 0; i < 16; i += 1) {
    tail += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `${time}${tail}`.slice(0, 26).padEnd(26, "0");
}

// Non-writing port of the legacy `emitMarkerResult`: build the SAME envelope it
// built (createCliResult with ok/complete:ok and the workspace/data/component
// trio) and return it with the exit code instead of writing stdout. The legacy
// caller returned `result.exit_code` for every command, so the exit code is the
// command result's own exit_code in all five cases.
function markerOutput(
  command: string,
  result: { exit_code: number },
  context: ResolvedContext,
  ok: boolean
): CommandOutput {
  return {
    envelope: createCliResult(command, result, {
      ok,
      complete: ok,
      workspaceRoot: context.workspace_root,
      dataRoot: context.data_root,
      componentId: context.component_id
    }),
    exitCode: result.exit_code
  };
}

// --- shared flag specs --------------------------------------------------------

// markerPaths reads these for EVERY marker command, so they are listed on each.
const markerPathFlags = [
  { key: "productRoot", name: "--product-root", kind: "string", valueName: "<path>", summary: "Root to scope markers/verifiers to (default --repo)." },
  { key: "bindings", name: "--bindings", kind: "string", valueName: "<path>", summary: "Override the bindings ledger path (default <data-root>/.use-cases/bindings.jsonl)." },
  { key: "proofs", name: "--proofs", kind: "string", valueName: "<path>", summary: "Override the proof ledger path (default <data-root>/.use-cases/proofs.jsonl)." }
] as const;

const trustedKeyFlags = [
  { key: "publicKey", name: "--public-key", kind: "string", valueName: "<path>", summary: "Trusted public key to verify proof signatures (else proofs read UNPROVEN)." },
  { key: "keyring", name: "--keyring", kind: "string", valueName: "<path>", summary: "Multi-key public-key registry (alternative to --public-key)." }
] as const;

// --- commands -----------------------------------------------------------------

export const markersBindCommand: CliCommand = {
  path: ["bind"],
  command: "markers.bind",
  summary: "Bind a use-case row to a code marker (inserts the marker into the source).",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    { key: "row", name: "--row", kind: "string", valueName: "<id>", summary: "Row id to bind." },
    { key: "file", name: "--file", kind: "string", valueName: "<path>", summary: "Source file to place the marker in." },
    { key: "mode", name: "--mode", kind: "string", valueName: "<mode>", summary: "explicit | swift-func." },
    { key: "startLine", name: "--start-line", kind: "integer", valueName: "<n>", summary: "Span start line (REQUIRED for --mode explicit)." },
    { key: "endLine", name: "--end-line", kind: "integer", valueName: "<n>", summary: "Span end line (REQUIRED for --mode explicit)." },
    { key: "line", name: "--line", kind: "integer", valueName: "<n>", summary: "Function line (REQUIRED for --mode swift-func)." },
    { key: "suffix", name: "--suffix", kind: "string", valueName: "<s>", summary: "Disambiguating suffix when a file binds more than one row." },
    { key: "registerExisting", name: "--register-existing", kind: "boolean", summary: "Register a marker already present in the source." },
    { key: "commentPrefix", name: "--comment-prefix", kind: "string", valueName: "<s>", summary: "Override the line-comment prefix (else inferred from extension/shebang)." },
    { key: "dryRun", name: "--dry-run", kind: "boolean", summary: "Preview the marker placement without writing the source or registry." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.bind");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const rowId = flags.row as string | undefined;
    const file = flags.file as string | undefined;
    // --register-existing registers an existing `//: @use-case:` marker span, so
    // it implies --mode explicit when no mode is given. `bind --help` lists --mode
    // as required only for a fresh bind, so requiring it here surprised users.
    const modeRaw = (flags.mode as string | undefined) ?? (flags.registerExisting ? "explicit" : undefined);
    if (!rowId || !file || (modeRaw !== "explicit" && modeRaw !== "swift-func")) {
      return {
        envelope: errorEnvelope("markers.bind", "cli_invalid_arguments", "Missing --row, --file, or --mode (explicit|swift-func)."),
        exitCode: 2
      };
    }
    const paths = markerPaths(flags, ctx);
    const result = runBindCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      rowId,
      suffix: flags.suffix as string | undefined,
      file,
      mode: modeRaw,
      line: flags.line as number | undefined,
      startLine: flags.startLine as number | undefined,
      endLine: flags.endLine as number | undefined,
      commentPrefix: flags.commentPrefix as string | undefined,
      registerExisting: flags.registerExisting as boolean,
      dryRun: flags.dryRun as boolean,
      clock: () => new Date().toISOString(),
      idFactory: generateUlid,
      version: getVersionInfo().version
    });
    return markerOutput("markers.bind", result, ctx, result.exit_code === 0);
  }
};

export const markersScanCommand: CliCommand = {
  path: ["scan"],
  command: "markers.scan",
  summary: "Scan code markers against the bindings ledger and report freshness.",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    { key: "policyMode", name: "--policy-mode", kind: "string", valueName: "<mode>", summary: "feature | release | custom." },
    { key: "gate", name: "--gate", kind: "boolean", summary: "Exit 1 when a required row is below the bar (release => FRESH, else >= VERIFIED_LOCAL). Off by default." },
    { key: "results", name: "--results", kind: "string", valueName: "<path>", summary: "Override the unsigned verify-results ledger feeding the keyless tier (default <data-root>/.use-cases/verification-results.jsonl)." },
    ...trustedKeyFlags,
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Override the generated-at timestamp." },
    { key: "baseRef", name: "--base-ref", kind: "string", valueName: "<ref>", summary: "Diff base for the append-only check." },
    { key: "ci", name: "--ci", kind: "boolean", summary: "CI mode (print inferred spans)." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.scan");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const paths = markerPaths(flags, ctx);
    const policyModeRaw = (flags.policyMode as string | undefined) ?? "feature";
    const policyMode = ["feature", "release", "custom"].includes(policyModeRaw)
      ? (policyModeRaw as "feature" | "release" | "custom")
      : "feature";
    const resultsRaw = flags.results as string | undefined;
    const result = runScanCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      policyMode,
      publicKeyResolver: markerPublicKeyResolver(flags),
      generatedAt: (flags.generatedAt as string | undefined) ?? new Date().toISOString(),
      baseRef: flags.baseRef as string | undefined,
      repoCwd: ctx.workspace_root,
      resultsPath: resultsRaw ? resolve(process.cwd(), resultsRaw) : undefined,
      gate: flags.gate as boolean
    });
    // CI mode prints the inferred spans to stderr (a human/log side-channel, NOT
    // the result envelope) before the dispatcher renders stdout. The dispatcher
    // has no stderr channel, so this side-effect stays here to keep behaviour
    // byte-identical with the legacy scan handler. Ordering (stderr then the
    // stdout envelope) is preserved because the handler runs before the render.
    if ((flags.ci as boolean) && result.inferred_spans.length > 0) {
      process.stderr.write(`${result.inferred_spans.join("\n\n")}\n`);
    }
    return markerOutput("markers.scan", result, ctx, result.exit_code === 0);
  }
};

export const markersImpactCommand: CliCommand = {
  path: ["impact"],
  command: "markers.impact",
  summary: "Show which bound behaviours a git change touches (advisory; re-verify the impacted ones).",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    ...trustedKeyFlags,
    { key: "base", name: "--base", kind: "string", valueName: "<ref>", summary: "Compare the working tree against this ref instead of HEAD." },
    { key: "staged", name: "--staged", kind: "boolean", summary: "Compare the staged index against HEAD instead of the working tree." },
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Override the generated-at timestamp." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.impact");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const paths = markerPaths(flags, ctx);
    const result = runImpactCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: markerPublicKeyResolver(flags),
      generatedAt: (flags.generatedAt as string | undefined) ?? new Date().toISOString(),
      base: flags.base as string | undefined,
      staged: flags.staged as boolean,
      repoCwd: ctx.workspace_root
    });
    return markerOutput("markers.impact", result, ctx, result.exit_code === 0);
  }
};

export const markersProveCommand: CliCommand = {
  path: ["prove"],
  command: "markers.prove",
  summary: "Mint SIGNED proofs from verification results (CI-only signing key).",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    { key: "row", name: "--row", kind: "string", valueName: "<id>", summary: "Target row id." },
    { key: "all", name: "--all", kind: "boolean", summary: "Target every bound row." },
    { key: "verificationResults", name: "--verification-results", kind: "string", valueName: "<path>", summary: "The results file written by `verify --out` (REQUIRED)." },
    { key: "trustedCi", name: "--trusted-ci", kind: "boolean", summary: "Mint as the trusted CI prover." },
    { key: "signingKeyEnv", name: "--signing-key-env", kind: "string", valueName: "<name>", summary: "Env var holding the signing key (CI secret)." },
    { key: "keyId", name: "--key-id", kind: "string", valueName: "<id>", summary: "Signing key id (default trusted-ci)." },
    { key: "authorityFile", name: "--authority-file", kind: "string", valueName: "<path>", summary: "Explicit CI authority record (JSON)." },
    { key: "append", name: "--append", kind: "boolean", summary: "Append minted proofs to the evidence ledger." },
    { key: "refresh", name: "--refresh", kind: "boolean", summary: "Re-mint proofs for rows whose context changed." },
    { key: "dryRun", name: "--dry-run", kind: "boolean", summary: "Preview without writing the evidence ledger." },
    { key: "unsafeAssumeVerificationResult", name: "--unsafe-assume-verification-result", kind: "string", valueName: "<result>", summary: "DANGEROUS: assume the row's verification passed (honoured only with UCM_ALLOW_UNSAFE_VERIFICATION=1)." },
    ...trustedKeyFlags,
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Override the generated-at timestamp." },
    { key: "baseRef", name: "--base-ref", kind: "string", valueName: "<ref>", summary: "Diff base for the append-only check." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.prove");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const all = flags.all as boolean;
    const rowId = flags.row as string | undefined;
    if (!all && !rowId) {
      return {
        envelope: errorEnvelope("markers.prove", "cli_invalid_arguments", "Missing --row or --all."),
        exitCode: 2
      };
    }
    const paths = markerPaths(flags, ctx);

    // prove no longer runs verifiers; it CONSUMES the unsigned verification-results
    // ledger that `verify --out` produced (one JSONL record per row).
    let verificationResults: VerificationResultRecord[] | undefined;
    const resultsPathRaw = flags.verificationResults as string | undefined;
    if (resultsPathRaw) {
      const resultsPath = resolve(process.cwd(), resultsPathRaw);
      let text: string;
      try {
        text = readFileSync(resultsPath, "utf8");
      } catch {
        return {
          envelope: errorEnvelope(
            "markers.prove",
            "cli_invalid_arguments",
            `Could not read --verification-results file: ${resultsPath}`
          ),
          exitCode: 2
        };
      }
      try {
        verificationResults = text
          .split("\n")
          .map((line) => line.trim())
          .filter((line) => line.length > 0)
          .map((line) => JSON.parse(line) as VerificationResultRecord);
      } catch {
        return {
          envelope: errorEnvelope(
            "markers.prove",
            "cli_invalid_arguments",
            `--verification-results file is not valid JSONL: ${resultsPath}`
          ),
          exitCode: 2
        };
      }
    }

    // DANGEROUS seam (renamed from --verification-result): assume the row's
    // verification passed. The core honours it ONLY when env
    // UCM_ALLOW_UNSAFE_VERIFICATION=1 is set; otherwise it is ignored.
    const unsafeAssume =
      (flags.unsafeAssumeVerificationResult as string | undefined) === "pass" ? ("pass" as const) : undefined;

    // CI-neutral provenance authority (additive, signed). An explicit
    // --authority-file (a JSON authority record) wins — for unknown CI / overrides;
    // otherwise auto-detect from the process env. The GitHub-shaped `producer` block
    // below is still populated exactly as before, beside the authority.
    let authority: CiAuthority;
    const authorityFileRaw = flags.authorityFile as string | undefined;
    if (authorityFileRaw) {
      const authorityPath = resolve(process.cwd(), authorityFileRaw);
      let authorityText: string;
      try {
        authorityText = readFileSync(authorityPath, "utf8");
      } catch {
        return {
          envelope: errorEnvelope(
            "markers.prove",
            "cli_invalid_arguments",
            `Could not read --authority-file: ${authorityPath}`
          ),
          exitCode: 2
        };
      }
      try {
        authority = JSON.parse(authorityText) as CiAuthority;
      } catch {
        return {
          envelope: errorEnvelope(
            "markers.prove",
            "cli_invalid_arguments",
            `--authority-file is not valid JSON: ${authorityPath}`
          ),
          exitCode: 2
        };
      }
    } else {
      authority = detectCiAuthority(process.env);
    }

    const result = runProveCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: markerPublicKeyResolver(flags),
      rowId,
      all,
      refresh: flags.refresh as boolean,
      trustedCi: flags.trustedCi as boolean,
      append: flags.append as boolean,
      dryRun: flags.dryRun as boolean,
      verificationResults,
      unsafeAssumeVerificationResult: unsafeAssume,
      signingKey: markerSigningKey(flags),
      producer: {
        ci_run_id: process.env.GITHUB_RUN_ID,
        repo: process.env.GITHUB_REPOSITORY,
        commit: process.env.GITHUB_SHA
      },
      authority,
      generatedAt: (flags.generatedAt as string | undefined) ?? new Date().toISOString(),
      idFactory: generateUlid,
      baseRef: flags.baseRef as string | undefined,
      repoCwd: ctx.workspace_root
    });
    return markerOutput("markers.prove", result, ctx, result.exit_code === 0);
  }
};

export const markersVerifyCommand: CliCommand = {
  path: ["verify"],
  command: "markers.verify",
  summary: "Run each bound row's verifier and write an UNSIGNED results ledger.",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    { key: "row", name: "--row", kind: "string", valueName: "<id>", summary: "Target row id." },
    { key: "all", name: "--all", kind: "boolean", summary: "Target every bound row." },
    { key: "out", name: "--out", kind: "string", valueName: "<path>", summary: "Write the unsigned results ledger (feed this to `prove --verification-results`). Keep it OUTSIDE the evidence dir." },
    ...trustedKeyFlags,
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Override the generated-at timestamp." },
    { key: "baseRef", name: "--base-ref", kind: "string", valueName: "<ref>", summary: "Diff base for the append-only check." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.verify");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const all = flags.all as boolean;
    const rowId = flags.row as string | undefined;
    if (!all && !rowId) {
      return {
        envelope: errorEnvelope("markers.verify", "cli_invalid_arguments", "Missing --all or --row <slug>."),
        exitCode: 2
      };
    }
    const paths = markerPaths(flags, ctx);
    // Default the unsigned results ledger to the SAME path `scan` auto-discovers
    // (<data-root>/.use-cases/verification-results.jsonl), so `verify` then `scan`
    // closes the keyless daily loop with ZERO flags. An explicit --out still wins.
    const outRaw = flags.out as string | undefined;
    const outPath = outRaw
      ? resolve(process.cwd(), outRaw)
      : join(ctx.data_root, ".use-cases", "verification-results.jsonl");
    const result = runVerifyCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver: markerPublicKeyResolver(flags),
      all,
      rowId,
      outPath,
      generatedAt: (flags.generatedAt as string | undefined) ?? new Date().toISOString(),
      baseRef: flags.baseRef as string | undefined,
      repoCwd: ctx.workspace_root
    });
    return markerOutput("markers.verify", result, ctx, result.exit_code === 0);
  }
};

export const markersValidateLedgerCommand: CliCommand = {
  path: ["validate-ledger"],
  command: "markers.validate-ledger",
  summary: "Validate the marker evidence ledger (append-only, signatures, schema).",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    ...trustedKeyFlags,
    { key: "baseRef", name: "--base-ref", kind: "string", valueName: "<ref>", summary: "Diff base for the append-only check." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.validate-ledger");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const paths = markerPaths(flags, ctx);
    const result = runValidateLedgerCommand({
      context: ctx,
      evidencePath: paths.evidencePath,
      bindingsPath: paths.bindingsPath,
      publicKeyResolver: markerPublicKeyResolver(flags),
      baseRef: flags.baseRef as string | undefined,
      repoCwd: ctx.workspace_root
    });
    // validate-ledger uses result.ok (NOT exit_code === 0) for the envelope ok/
    // complete flags, exactly as the legacy handler did.
    return markerOutput("markers.validate-ledger", result, ctx, result.ok);
  }
};

export const markersCommands: CliCommand[] = [
  markersBindCommand,
  markersScanCommand,
  markersImpactCommand,
  markersProveCommand,
  markersVerifyCommand,
  markersValidateLedgerCommand
];
