// `uc recover` — drive a drifted / unproven row back to green in ONE command.
//
// The fleet found recovery non-obvious: a row that has drifted (STALE_LOCAL) or
// was never verified (UNVERIFIED_LOCAL / UNPROVEN) needs a re-verify, and — for
// the signed tier — a re-prove. `recover` composes the EXISTING command cores
// (verify, optional prove, scan) behind a single, well-messaged verb. It adds NO
// new trust logic:
//
//   recover --row <id> | --all
//     1. verify the target row(s) — reuse runVerifyCommand — and WRITE the
//        unsigned results ledger to the canonical auto-discover path
//        (<data_root>/.use-cases/verification-results.jsonl).
//     2. if the verifier GENUINELY FAILS, stop and return a non-zero exit with an
//        actionable diagnostic naming the failing row(s). NEVER fake green.
//     3. with --signing-key-env <ENV>, additionally PROVE the row(s) to FRESH
//        (trusted-CI signing, appended to the evidence ledger).
//     4. re-scan and report the resulting local_status + status per row.
//
// The command lives in its OWN file (not markers.ts) so it composes the marker
// cores without touching the scan / verify / prove command specs. The thin
// marker helpers it needs (path resolution, key resolvers, ULID) are small and
// re-implemented here rather than reaching into markers.ts internals.
import { createPrivateKey, createPublicKey } from "node:crypto";
import { readFileSync } from "node:fs";
import { join, resolve } from "node:path";
import type { CliCommand, CommandOutput, ParsedFlags } from "../command/types.js";
import {
  createCliResult,
  DEFAULT_VERIFICATION_RESULTS_FILENAME,
  detectCiAuthority,
  errorEnvelope,
  keyringPublicKeyResolverFromFile,
  resolveContextOrError,
  runProveCommand,
  runScanCommand,
  runVerifyCommand,
  singleKeyResolver,
  type ResolvedContext
} from "../runtime.js";
import { loadUcmCore } from "../coreLoader.js";
import { workspaceFlags } from "./common.js";

const { getVersionInfo } = await loadUcmCore();

// --- thin, self-contained marker helpers (mirror markers.ts, no cross-import) --

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

// The canonical UNSIGNED results ledger `scan` auto-discovers. recover writes it
// here explicitly so the subsequent scan (and any later scan) picks it up with no
// --results flag — the zero-config keyless loop.
function defaultResultsPath(context: ResolvedContext): string {
  return join(context.data_root, ".use-cases", DEFAULT_VERIFICATION_RESULTS_FILENAME);
}

function keyMaterialError(kind: "signing" | "public", origin: string, cause: unknown): Error {
  const detail = cause instanceof Error ? cause.message : String(cause);
  const error = new Error(
    `The ${kind} key (${origin}) is not a valid PEM key — expected a PKCS8 ed25519 PEM. ` +
      `See docs/security/key-management.md to generate one. (${detail})`
  );
  (error as { code?: string }).code = kind === "signing" ? "signing_key.invalid" : "public_key.invalid";
  return error;
}

function markerPublicKeyResolver(flags: ParsedFlags): ReturnType<typeof singleKeyResolver> {
  const keyringPath = flags.keyring as string | undefined;
  if (keyringPath) {
    return keyringPublicKeyResolverFromFile(resolve(process.cwd(), keyringPath));
  }
  const keyPath = flags.publicKey as string | undefined;
  if (!keyPath) {
    return () => undefined;
  }
  const pem = readFileSync(resolve(process.cwd(), keyPath), "utf8");
  try {
    return singleKeyResolver(createPublicKey(pem));
  } catch (error) {
    throw keyMaterialError("public", keyPath, error);
  }
}

function markerSigningKey(
  flags: ParsedFlags
): { privateKey: ReturnType<typeof createPrivateKey>; keyId: string } | undefined {
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

function generateUlid(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  const time = Date.now().toString(32).toUpperCase().padStart(10, "0").slice(0, 10);
  let tail = "";
  for (let i = 0; i < 16; i += 1) {
    tail += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return `${time}${tail}`.slice(0, 26).padEnd(26, "0");
}

// --- the recover command ------------------------------------------------------

const trustedKeyFlags = [
  { key: "publicKey", name: "--public-key", kind: "string", valueName: "<path>", summary: "Trusted public key to verify proof signatures (needed for --signing-key-env to read FRESH)." },
  { key: "keyring", name: "--keyring", kind: "string", valueName: "<path>", summary: "Multi-key public-key registry (alternative to --public-key)." }
] as const;

const markerPathFlags = [
  { key: "productRoot", name: "--product-root", kind: "string", valueName: "<path>", summary: "Root to scope markers/verifiers to (default --repo)." },
  { key: "bindings", name: "--bindings", kind: "string", valueName: "<path>", summary: "Override the bindings ledger path (default <data-root>/.use-cases/bindings.jsonl)." },
  { key: "proofs", name: "--proofs", kind: "string", valueName: "<path>", summary: "Override the proof ledger path (default <data-root>/.use-cases/proofs.jsonl)." }
] as const;

export const recoverCommand: CliCommand = {
  path: ["recover"],
  command: "markers.recover",
  summary: "Drive a drifted / unproven row back to green: re-verify (and optionally re-prove), then report.",
  flags: [
    ...workspaceFlags,
    ...markerPathFlags,
    { key: "row", name: "--row", kind: "string", valueName: "<id>", summary: "Target row id." },
    { key: "all", name: "--all", kind: "boolean", summary: "Target every bound row." },
    { key: "signingKeyEnv", name: "--signing-key-env", kind: "string", valueName: "<name>", summary: "Env var holding the signing key (CI secret) — ALSO re-prove the row(s) to FRESH." },
    { key: "keyId", name: "--key-id", kind: "string", valueName: "<id>", summary: "Signing key id (default trusted-ci)." },
    ...trustedKeyFlags,
    { key: "generatedAt", name: "--generated-at", kind: "string", valueName: "<iso>", summary: "Override the generated-at timestamp." },
    { key: "baseRef", name: "--base-ref", kind: "string", valueName: "<ref>", summary: "Diff base for the append-only check." }
  ],
  handler: ({ argv, flags }) => {
    const context = resolveContextOrError(argv, "markers.recover");
    if (context.kind === "error") {
      return { envelope: context.envelope, exitCode: context.exitCode };
    }
    const ctx = context.context;
    const all = flags.all as boolean;
    const rowId = flags.row as string | undefined;
    if (!all && !rowId) {
      return {
        envelope: errorEnvelope("markers.recover", "cli_invalid_arguments", "Missing --row <id> or --all."),
        exitCode: 2
      };
    }

    const paths = markerPaths(flags, ctx);
    const publicKeyResolver = markerPublicKeyResolver(flags);
    const generatedAt = (flags.generatedAt as string | undefined) ?? new Date().toISOString();
    const baseRef = flags.baseRef as string | undefined;
    const resultsPath = defaultResultsPath(ctx);
    const targetLabel = all ? "--all" : rowId!;

    // Validate the signing key BEFORE running the verifier or writing the
    // ledger — a detectable usage error must not have side effects.
    const signingKey = markerSigningKey(flags);
    if (flags.signingKeyEnv !== undefined && !signingKey) {
      return {
        envelope: errorEnvelope(
          "markers.recover",
          "cli_invalid_arguments",
          `--signing-key-env ${String(flags.signingKeyEnv)} is set but $${String(flags.signingKeyEnv)} is empty — provide the PKCS8 ed25519 private key PEM in that env var (a CI secret).`
        ),
        exitCode: 2
      };
    }

    // --- Step 1: re-run the verifier(s), writing the canonical unsigned ledger.
    const verifyResult = runVerifyCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      publicKeyResolver,
      all,
      rowId,
      outPath: resultsPath,
      generatedAt,
      baseRef,
      repoCwd: ctx.workspace_root
    });

    // --- Step 2: honour a genuine failure. NEVER fake green. If the verifier ran
    // and any target row FAILED (or verify itself errored), stop with a non-zero
    // exit and an actionable diagnostic naming the offending row(s).
    const failedRows = verifyResult.results.filter((r) => r.status !== "pass").map((r) => r.row_id);
    if (verifyResult.exit_code !== 0 || failedRows.length > 0) {
      const named = failedRows.length > 0 ? failedRows.join(", ") : targetLabel;
      const diagnostics = [
        {
          code: "recover.verification_failed",
          severity: "error" as const,
          message:
            `recover could not restore ${named} to green: the verifier failed for ${named}. ` +
            `Fix the code or the test so the row's verifier passes, then re-run \`uc recover\`. ` +
            `Inspect the failure with \`uc verify --repo ${ctx.workspace_root} ${all ? "--all" : `--row ${rowId}`}\`.`,
          source_path: null,
          json_pointer: null,
          entity_id: failedRows[0] ?? rowId ?? null,
          related_ids: failedRows
        }
      ];
      return {
        envelope: createCliResult(
          "markers.recover",
          {
            recovered: false,
            proved: false,
            verify: verifyResult,
            failed_rows: failedRows
          },
          {
            ok: false,
            complete: false,
            workspaceRoot: ctx.workspace_root,
            dataRoot: ctx.data_root,
            componentId: ctx.component_id,
            diagnostics
          }
        ),
        // 1 = "command failed" bucket (the verifier genuinely did not pass).
        exitCode: 1
      };
    }

    // --- Step 3 (optional): re-prove to FRESH when a signing key is supplied
    // (already validated above, before any side effects).
    let proveResult: ReturnType<typeof runProveCommand> | undefined;
    if (signingKey) {
      proveResult = runProveCommand({
        context: ctx,
        productRoot: paths.productRoot,
        bindingsPath: paths.bindingsPath,
        evidencePath: paths.evidencePath,
        publicKeyResolver,
        rowId,
        all,
        refresh: true,
        trustedCi: true,
        append: true,
        dryRun: false,
        verificationResults: verifyResult.results,
        unsafeAssumeVerificationResult: undefined,
        signingKey,
        producer: {
          ci_run_id: process.env.GITHUB_RUN_ID,
          repo: process.env.GITHUB_REPOSITORY,
          commit: process.env.GITHUB_SHA
        },
        authority: detectCiAuthority(process.env),
        generatedAt,
        idFactory: generateUlid,
        baseRef,
        repoCwd: ctx.workspace_root
      });
      // A prove failure here means the signed tier could not be established even
      // though the verifier passed — surface it, non-zero, without faking green.
      if (proveResult.exit_code !== 0) {
        return {
          envelope: createCliResult(
            "markers.recover",
            { recovered: false, proved: false, verify: verifyResult, prove: proveResult },
            {
              ok: false,
              complete: false,
              workspaceRoot: ctx.workspace_root,
              dataRoot: ctx.data_root,
              componentId: ctx.component_id,
              diagnostics: [
                {
                  code: "recover.prove_failed",
                  severity: "error" as const,
                  message:
                    `recover re-verified ${targetLabel} but could not mint a signed proof. ` +
                    `Check the signing key ($${String(flags.signingKeyEnv)}) and the trusted-CI authority.`,
                  source_path: null,
                  json_pointer: null,
                  entity_id: rowId ?? null,
                  related_ids: []
                }
              ]
            }
          ),
          exitCode: 1
        };
      }
    }

    // --- Step 4: re-scan and report the resulting local_status + status.
    const scanResult = runScanCommand({
      context: ctx,
      productRoot: paths.productRoot,
      bindingsPath: paths.bindingsPath,
      evidencePath: paths.evidencePath,
      policyMode: "feature",
      publicKeyResolver,
      generatedAt,
      baseRef,
      repoCwd: ctx.workspace_root
    });

    // --- Step 5: CONFIRM the re-scan actually put the target row(s) at the
    // intended bar before reporting success. A passing verifier ALONE is not
    // enough: a signed proof we cannot read back (no --public-key), a
    // pre-existing ledger-integrity error (scan exit 3/4), or an unbound target
    // must all surface as NON-green — never a fake exit-0. The bar is FRESH when
    // we re-proved, else VERIFIED_LOCAL (the keyless green).
    const wantFresh = signingKey !== undefined;
    const bar = wantFresh ? "FRESH" : "VERIFIED_LOCAL";
    const scanRows = scanResult.status?.rows ?? [];
    const rowById = new Map(scanRows.map((row) => [row.row_id, row]));
    // Verify records a variant family per variant (`<family>::<key>`), but scan
    // reports at the FAMILY level (the family row aggregates its variants). Map
    // every result back to its family id — otherwise a green variant family reads
    // as "not green" here forever, purely because the lookup key never matches.
    const familyRowId = (id: string): string => {
      const separator = id.indexOf("::");
      return separator < 0 ? id : id.slice(0, separator);
    };
    const targetRowIds = all
      ? [...new Set(verifyResult.results.map((r) => familyRowId(r.row_id)))]
      : [rowId!];
    const notGreen = targetRowIds.filter((id) => {
      const row = rowById.get(id);
      const reached = wantFresh
        ? row?.status === "FRESH"
        : row?.status === "FRESH" || row?.local_status === "VERIFIED_LOCAL";
      return !reached;
    });

    const recovered =
      scanResult.exit_code === 0 && targetRowIds.length > 0 && notGreen.length === 0;
    if (!recovered) {
      const named = notGreen.length > 0 ? notGreen.join(", ") : targetLabel;
      const needsPublicKey =
        wantFresh && flags.publicKey === undefined && flags.keyring === undefined;
      const hint = needsPublicKey
        ? "To read back the freshly signed proof, also pass --public-key <path> (the public half of --signing-key-env)."
        : scanResult.exit_code !== 0
          ? `\`uc scan\` reported an integrity error (exit ${scanResult.exit_code}) — resolve it, then re-run \`uc recover\`.`
          : `Inspect the current state with \`uc scan --repo ${ctx.workspace_root}\`.`;
      return {
        envelope: createCliResult(
          "markers.recover",
          {
            recovered: false,
            proved: proveResult !== undefined,
            target: targetLabel,
            results_path: resultsPath,
            verify: verifyResult,
            ...(proveResult ? { prove: proveResult } : {}),
            status: scanResult.status
          },
          {
            ok: false,
            complete: false,
            workspaceRoot: ctx.workspace_root,
            dataRoot: ctx.data_root,
            componentId: ctx.component_id,
            diagnostics: [
              {
                code: "recover.not_green",
                severity: "error" as const,
                message: `recover re-verified ${targetLabel} but ${named} did not reach ${bar}. ${hint}`,
                source_path: null,
                json_pointer: null,
                entity_id: notGreen[0] ?? rowId ?? null,
                related_ids: notGreen
              }
            ]
          }
        ),
        exitCode: scanResult.exit_code !== 0 ? scanResult.exit_code : 1
      };
    }

    return {
      envelope: createCliResult(
        "markers.recover",
        {
          recovered: true,
          proved: proveResult !== undefined,
          target: targetLabel,
          results_path: resultsPath,
          verify: verifyResult,
          ...(proveResult ? { prove: proveResult } : {}),
          // Mirror scan's shape so callers can read data.status.rows[].local_status
          // and .status exactly as they do from `uc scan`.
          status: scanResult.status
        },
        {
          ok: true,
          complete: true,
          workspaceRoot: ctx.workspace_root,
          dataRoot: ctx.data_root,
          componentId: ctx.component_id
        }
      ),
      exitCode: 0
    } satisfies CommandOutput;
  }
};

export const recoverCommands: CliCommand[] = [recoverCommand];
