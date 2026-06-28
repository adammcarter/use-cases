// `prove` command core (spec 8.3; Phase 7).
//
// Runs scan first, refuses INVALID/UNBOUND rows, runs the row's verification
// policy through an INJECTED runner (so tests never shell out), and — only on a
// pass and only in trusted-CI mode — recomputes every hash ITSELF, signs the
// proof event with an ed25519 key, and appends it to the evidence ledger. It never
// accepts caller-supplied hashes and never lets an agent set producer.kind. Exit
// codes follow spec 8.3 (0/2/3/4/5/6).
import type { ResolvedWorkspaceContext } from "../../roots.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import { ROW_HASH_ID, SPAN_CANON_ID, BINDING_SET_HASH_ID } from "../constants.js";
import { computeRowHash } from "../rowHash.js";
import {
  computeApprovalPolicyHash,
  computeVerificationPolicyHash
} from "../policyHash.js";
import { computeBindingSetHash } from "../bindingSetHash.js";
import {
  VERIFICATION_CONTEXT_HASH_ID,
  computeRowVerificationContextHash
} from "../verificationContextHash.js";
import { TRUSTED_CI_PRODUCER_KIND, type ProofEvent } from "../evidenceLedger.js";
import {
  signEvent,
  type PemOrKeyObject,
  type PublicKeyResolver
} from "../proofSignature.js";
import type { CurrentBindingRecord } from "../scanner.js";
import type { FreshnessInputRow } from "../freshness.js";
import type { GitRunner } from "../appendOnly.js";
import { appendJsonlLine, nodeMarkerFs, type MarkerFs } from "./io.js";
import { prepareScan } from "./scan.js";
import { registeredBindingsForRow } from "./shared.js";

export interface VerificationContext {
  row_id: string;
  row: FreshnessInputRow;
  bindings: CurrentBindingRecord[];
}

export interface VerificationOutcome {
  result: "pass" | "fail";
  command_id: string;
  started_at: string;
  completed_at: string;
  artifacts?: Array<{ kind: string; path: string; sha256: string }>;
}

// Injected so prove never shells out in tests (spec 8.3 "inject the runner").
export type VerificationRunner = (ctx: VerificationContext) => VerificationOutcome;

export interface ProveSigningKey {
  privateKey: PemOrKeyObject;
  keyId: string;
}

export interface ProveProducerInfo {
  id?: string;
  version?: string;
  ci_run_id?: string;
  repo?: string;
  commit?: string;
}

export interface ProveCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  evidencePath: string;
  publicKeyResolver: PublicKeyResolver;
  rowId: string;
  trustedCi?: boolean;
  // An explicit append request; without trusted credentials this is exit 6.
  append?: boolean;
  dryRun?: boolean;
  verificationRunner: VerificationRunner;
  signingKey?: ProveSigningKey;
  producer?: ProveProducerInfo;
  generatedAt: string;
  // Injectable so tests can assert on a deterministic event id.
  idFactory?: () => string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
  baseRef?: string;
  gitRunner?: GitRunner;
  repoCwd?: string;
}

export interface ProveCommandResult {
  exit_code: number;
  ok: boolean;
  command: "prove";
  trusted: boolean;
  row_id: string;
  verification_result: "pass" | "fail" | "not_run";
  proof_event_appended: boolean;
  event_id: string | null;
  row_hash: string | null;
  binding_set_hash: string | null;
  errors: Array<{ code: string; message: string }>;
}

function result(
  partial: Partial<ProveCommandResult> & { exit_code: number; row_id: string }
): ProveCommandResult {
  return {
    command: "prove",
    ok: partial.exit_code === 0,
    trusted: partial.trusted ?? false,
    verification_result: partial.verification_result ?? "not_run",
    proof_event_appended: partial.proof_event_appended ?? false,
    event_id: partial.event_id ?? null,
    row_hash: partial.row_hash ?? null,
    binding_set_hash: partial.binding_set_hash ?? null,
    errors: partial.errors ?? [],
    ...partial
  };
}

export function runProveCommand(options: ProveCommandOptions): ProveCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const trusted = options.trustedCi === true;

  // Untrusted explicit append attempt is the highest-priority refusal (spec 8.3).
  if (options.append && !trusted) {
    return result({
      exit_code: 6,
      row_id: options.rowId,
      errors: [
        {
          code: "UNTRUSTED_APPEND",
          message: "an append was requested without trusted-CI credentials"
        }
      ]
    });
  }

  // Run scan first (spec 8.3 step 1).
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
    baseRef: options.baseRef,
    gitRunner: options.gitRunner,
    repoCwd: options.repoCwd
  });

  // Ledger/registry validation failure -> exit 4.
  if (prepared.registryErrors.length > 0 || prepared.evidenceErrors.length > 0) {
    return result({
      exit_code: 4,
      row_id: options.rowId,
      trusted,
      errors: [{ code: "LEDGER_INVALID", message: "registry or evidence ledger failed validation" }]
    });
  }

  const statusRow = prepared.status.rows.find((row) => row.row_id === options.rowId);
  const row = prepared.loaded.rows.find((entry) => entry.row_id === options.rowId);
  if (!statusRow || !row) {
    return result({
      exit_code: 2,
      row_id: options.rowId,
      trusted,
      errors: [{ code: "ROW_NOT_FOUND", message: `row ${options.rowId} is not a known use-case row` }]
    });
  }

  // Refuse INVALID (spec 8.3 step 2) -> exit 3; refuse UNBOUND (step 3) -> exit 2.
  if (statusRow.status === "INVALID") {
    return result({
      exit_code: 3,
      row_id: options.rowId,
      trusted,
      errors: [{ code: "ROW_INVALID", message: `row ${options.rowId} has binding integrity errors; cannot prove` }]
    });
  }
  if (statusRow.status === "UNBOUND") {
    return result({
      exit_code: 2,
      row_id: options.rowId,
      trusted,
      errors: [{ code: "ROW_UNBOUND", message: `row ${options.rowId} has no binding; nothing to prove` }]
    });
  }

  // Run the verification policy through the injected runner (spec 8.3 step 4).
  const registeredSlugs = new Set(statusRow.known_binding_slugs);
  const bindings = registeredBindingsForRow(prepared.scan.bindings, options.rowId, registeredSlugs);
  const outcome = options.verificationRunner({ row_id: options.rowId, row, bindings });

  if (outcome.result !== "pass") {
    // Never append on failure (spec 8.3 must-not 1) -> exit 5.
    return result({
      exit_code: 5,
      row_id: options.rowId,
      trusted,
      verification_result: "fail",
      errors: [{ code: "VERIFICATION_FAILED", message: `verification for ${options.rowId} did not pass` }]
    });
  }

  // On pass, recompute every hash from scratch (spec 8.3 steps 5-7; never trust
  // caller-supplied hashes).
  const rowHash = computeRowHash(row);
  const verificationPolicyHash = computeVerificationPolicyHash(row.verification_policy);
  const approvalPolicyHash = computeApprovalPolicyHash(row.approval_policy);
  const bindingSetHash = computeBindingSetHash(
    options.rowId,
    bindings.map((binding) => ({
      binding_slug: binding.binding_slug,
      row_id: binding.row_id,
      file_path: binding.file_path,
      extent_kind: binding.extent_kind,
      recognizer_id: binding.recognizer_id,
      span_canon_id: binding.span_canon_id,
      span_sha256: binding.span.sha256
    }))
  );
  // Bind the proof to its verifier context (policy + resolved verifier + declared
  // input contents + lockfile). Re-derived identically at scan time, so the proof
  // drops out of FRESH if the verifier or its acceptance test is later weakened.
  const contextHash = computeRowVerificationContextHash({
    slug: options.rowId,
    verificationPolicy: row.verification_policy,
    rootDir: options.repoCwd ?? options.productRoot,
    fs
  });

  // Candidate-only when not trusted, or when explicitly dry-run (spec 8.3 local
  // behavior). MUST NOT append a proof event.
  if (!trusted || options.dryRun) {
    return result({
      exit_code: 0,
      row_id: options.rowId,
      trusted,
      verification_result: "pass",
      proof_event_appended: false,
      row_hash: rowHash,
      binding_set_hash: bindingSetHash
    });
  }

  // Trusted append requires a signing key (config error otherwise).
  if (!options.signingKey) {
    return result({
      exit_code: 2,
      row_id: options.rowId,
      trusted,
      verification_result: "pass",
      errors: [{ code: "SIGNING_KEY_MISSING", message: "trusted-CI prove requires a signing key" }]
    });
  }

  const unsigned = buildProofEvent({
    eventId: (options.idFactory ?? generateEventId)(),
    createdAt: options.generatedAt,
    rowId: options.rowId,
    rowHash,
    verificationPolicyHash,
    approvalPolicyHash,
    bindingSetHash,
    contextHash,
    bindings,
    outcome,
    producer: options.producer
  });
  const signed = signEvent(unsigned, options.signingKey.privateKey, options.signingKey.keyId);

  appendJsonlLine(fs, options.evidencePath, JSON.stringify(signed));

  return result({
    exit_code: 0,
    row_id: options.rowId,
    trusted: true,
    verification_result: "pass",
    proof_event_appended: true,
    event_id: signed.event_id,
    row_hash: rowHash,
    binding_set_hash: bindingSetHash
  });
}

// 26-char Crockford-base32 ULID-shaped id. Deterministic ids are injectable via
// `idFactory` for tests that assert on event ids; here uniqueness is what matters.
function generateEventId(): string {
  const alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
  let out = "";
  for (let i = 0; i < 26; i += 1) {
    out += alphabet[Math.floor(Math.random() * alphabet.length)];
  }
  return out;
}

interface BuildProofArgs {
  eventId: string;
  createdAt: string;
  rowId: string;
  rowHash: string;
  verificationPolicyHash: string;
  approvalPolicyHash: string;
  bindingSetHash: string;
  contextHash: string;
  bindings: CurrentBindingRecord[];
  outcome: VerificationOutcome;
  producer?: ProveProducerInfo;
}

// Build the unsigned proof event. producer.kind is ALWAYS forced to the trusted
// constant — an agent can never set it (spec 8.3 must-not 5).
function buildProofEvent(args: BuildProofArgs): Omit<ProofEvent, "signature"> {
  return {
    schema: "ucase-proof-event-v1",
    event_type: "row_proof_passed",
    event_id: args.eventId,
    created_at: args.createdAt,
    producer: {
      kind: TRUSTED_CI_PRODUCER_KIND,
      id: args.producer?.id ?? "ci/use-cases-prover",
      version: args.producer?.version ?? "0.1.0",
      ci_run_id: args.producer?.ci_run_id ?? "local",
      repo: args.producer?.repo ?? "unknown/unknown",
      commit: args.producer?.commit ?? "0".repeat(40)
    },
    row: {
      row_id: args.rowId,
      row_hash_id: ROW_HASH_ID,
      row_hash: args.rowHash,
      verification_policy_hash: args.verificationPolicyHash,
      approval_policy_hash: args.approvalPolicyHash
    },
    bindings: {
      binding_set_hash_id: BINDING_SET_HASH_ID,
      binding_set_hash: args.bindingSetHash,
      span_canon_id: SPAN_CANON_ID,
      items: args.bindings.map((binding) => ({
        binding_slug: binding.binding_slug,
        row_id: binding.row_id,
        file_path: binding.file_path,
        extent_kind: binding.extent_kind,
        recognizer_id: binding.recognizer_id,
        span_canon_id: binding.span_canon_id,
        span_sha256: binding.span.sha256,
        span_start_line: binding.span.start_line,
        span_end_line: binding.span.end_line
      }))
    },
    verification: {
      command_id: args.outcome.command_id,
      result: "pass",
      started_at: args.outcome.started_at,
      completed_at: args.outcome.completed_at,
      artifacts: args.outcome.artifacts ?? [],
      context_hash_id: VERIFICATION_CONTEXT_HASH_ID,
      context_hash: args.contextHash
    }
  };
}
