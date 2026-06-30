// Precommit orchestrator + PR-summary formatter (spec 10.1, 10.2; Phase 8).
//
// These are PURE functions: they take the already-computed results of the
// `validate-ledger` (staged) and `scan --policy-mode <mode>` command cores and
// decide BLOCK vs WARN vs OK (10.1), or render a human-readable PR summary from a
// freshness status object (10.2). They never shell out, never touch the
// filesystem, and never re-run the scan/ledger logic -- the thin precommit shell
// script and the CI workflow run the CLI commands and feed their results here.
//
// Block vs warn (spec 10.1):
//   BLOCK  validate-ledger failed (non-append edit, bad/unsigned/invalid proof,
//          registry conflict, schema failure), OR scan found an INVALID row
//          (malformed marker, duplicate slug, unclosed/mismatched end,
//          unsupported inferred marker, unregistered current marker), OR scan's
//          ledger/registry validation failed, OR any row is freshness
//          policy-blocked (release: a required row that is not FRESH).
//   WARN   a SUSPECT / UNPROVEN / UNBOUND row that the policy does NOT block --
//          printed loudly with its required action, but the commit proceeds.
//   OK     nothing of concern.
import type { FreshnessRowOut, FreshnessStatus } from "../freshness.js";
import type { ScanCommandResult } from "./scan.js";
import type { ValidateLedgerCommandResult } from "./validateLedger.js";

export type PrecommitDecision = "BLOCK" | "WARN" | "OK";

export interface PrecommitBlockReason {
  source: "validate-ledger" | "scan";
  code: string;
  row_id?: string;
  message: string;
}

export interface PrecommitWarning {
  row_id: string;
  status: "SUSPECT" | "UNPROVEN" | "UNBOUND";
  reason: string;
  required_action: string;
  // The loud, multi-line warning block (spec 10.1).
  message: string;
}

export interface PrecommitResult {
  decision: PrecommitDecision;
  // 1 when BLOCK (so the git hook aborts), 0 for WARN/OK (commit proceeds).
  exit_code: number;
  block_reasons: PrecommitBlockReason[];
  warnings: PrecommitWarning[];
  // All human-readable lines (block reasons followed by loud warnings), for the
  // hook/CI to print directly.
  messages: string[];
}

// Only the fields the orchestrator reads from each command result. Accepting the
// full result types is fine too -- these slices keep the contract explicit and
// the unit tests hand-buildable.
export interface PrecommitInput {
  validateLedger: Pick<
    ValidateLedgerCommandResult,
    "ok" | "exit_code" | "evidence_valid" | "registry_valid" | "append_only" | "errors"
  >;
  scan: Pick<ScanCommandResult, "exit_code" | "registry_valid" | "evidence_valid" | "status">;
}

const WARN_STATUSES: ReadonlySet<string> = new Set(["SUSPECT", "UNPROVEN", "UNBOUND"]);

function firstReasonCode(row: FreshnessRowOut): string {
  return row.reasons[0]?.code ?? row.status;
}

function defaultRequiredAction(row: FreshnessRowOut): string {
  if (row.required_action) {
    return row.required_action;
  }
  return row.status === "UNBOUND"
    ? `ucp bind --row ${row.row_id}`
    : `ucp prove --row ${row.row_id}`;
}

// Build the loud warning block exactly as spec 10.1 mandates for SUSPECT (the
// status word and reason vary by row).
export function formatPrecommitWarning(row: FreshnessRowOut): PrecommitWarning {
  const reason = firstReasonCode(row);
  const requiredAction = defaultRequiredAction(row);
  const message = [
    `USE-CASE ROW ${row.status}`,
    `row: ${row.row_id}`,
    `reason: ${reason}`,
    `required action: ${requiredAction}`
  ].join("\n");
  return {
    row_id: row.row_id,
    status: row.status as PrecommitWarning["status"],
    reason,
    required_action: requiredAction,
    message
  };
}

export function decidePrecommit(input: PrecommitInput): PrecommitResult {
  const blockReasons: PrecommitBlockReason[] = [];
  const warnings: PrecommitWarning[] = [];

  // --- validate-ledger: any failure blocks (spec 10.1 items 6-10). ---
  if (!input.validateLedger.ok) {
    if (input.validateLedger.errors.length > 0) {
      for (const error of input.validateLedger.errors) {
        blockReasons.push({
          source: "validate-ledger",
          code: error.code,
          message: `validate-ledger (${error.scope}): ${error.message}`
        });
      }
    } else {
      blockReasons.push({
        source: "validate-ledger",
        code: "LEDGER_INVALID",
        message: "validate-ledger reported the evidence ledger or binding registry as invalid"
      });
    }
  }

  // --- scan: ledger/registry validation failures (exit 4) block too. ---
  if (!input.scan.registry_valid || !input.scan.evidence_valid) {
    const ledgerIntegrity = input.scan.status.integrity_errors.filter(
      (error) => error.row_id === undefined
    );
    if (ledgerIntegrity.length > 0) {
      for (const error of ledgerIntegrity) {
        blockReasons.push({
          source: "scan",
          code: error.code,
          message: `scan ledger/registry: ${error.message ?? error.code}`
        });
      }
    } else {
      blockReasons.push({
        source: "scan",
        code: "LEDGER_INVALID",
        message: "scan reported the evidence ledger or binding registry as invalid"
      });
    }
  }

  // --- scan: usage/config/internal error (exit 2) blocks. ---
  if (input.scan.exit_code === 2) {
    blockReasons.push({
      source: "scan",
      code: "SCAN_USAGE_ERROR",
      message: "scan failed with a usage/config/internal error (exit 2)"
    });
  }

  // --- per-row: INVALID blocks; policy-blocked rows block; warn statuses warn. ---
  for (const row of input.scan.status.rows) {
    if (row.status === "INVALID") {
      blockReasons.push({
        source: "scan",
        code: firstReasonCode(row),
        row_id: row.row_id,
        message: `INVALID row ${row.row_id}: ${firstReasonCode(row)}`
      });
      continue;
    }
    if (row.policy_block) {
      // A non-INVALID row the policy blocks: in release mode, a required row that
      // is not FRESH (spec 10.2). Surfaced as a block, not a soft warning.
      blockReasons.push({
        source: "scan",
        code: "FRESHNESS_POLICY_BLOCK",
        row_id: row.row_id,
        message:
          `freshness policy blocks ${row.row_id} (status ${row.status}); ` +
          `${defaultRequiredAction(row)}`
      });
      continue;
    }
    if (WARN_STATUSES.has(row.status)) {
      warnings.push(formatPrecommitWarning(row));
    }
  }

  const decision: PrecommitDecision =
    blockReasons.length > 0 ? "BLOCK" : warnings.length > 0 ? "WARN" : "OK";

  const messages: string[] = [
    ...blockReasons.map((reason) => `BLOCK: ${reason.message}`),
    ...warnings.map((warning) => warning.message)
  ];

  return {
    decision,
    exit_code: decision === "BLOCK" ? 1 : 0,
    block_reasons: blockReasons,
    warnings,
    messages
  };
}

// ---------------------------------------------------------------------------
// PR-summary formatter (spec 10.2 "textual summary"): a freshness status object
// -> a human-readable block of counts + each SUSPECT/INVALID row with its
// required action + the inferred Swift spans. Pure and deterministic.
// ---------------------------------------------------------------------------
export function formatFreshnessPrSummary(status: FreshnessStatus): string {
  const lines: string[] = [];
  lines.push(`USE-CASE FRESHNESS SUMMARY (policy: ${status.policy_mode})`);
  const summary = status.summary;
  lines.push(
    `fresh: ${summary.fresh}  suspect: ${summary.suspect}  unproven: ${summary.unproven}  ` +
      `unbound: ${summary.unbound}  invalid: ${summary.invalid}  policy_blocked: ${summary.policy_blocked}`
  );

  const invalidRows = status.rows.filter((row) => row.status === "INVALID");
  lines.push("");
  lines.push("INVALID rows:");
  if (invalidRows.length === 0) {
    lines.push("- (none)");
  } else {
    for (const row of invalidRows) {
      lines.push(`- ${row.row_id}  reason: ${firstReasonCode(row)}`);
      lines.push(`  required action: ${defaultRequiredAction(row)}`);
    }
  }

  const suspectRows = status.rows.filter(
    (row) => row.status === "SUSPECT" || row.status === "UNPROVEN" || row.status === "UNBOUND"
  );
  lines.push("");
  lines.push("SUSPECT / UNPROVEN / UNBOUND rows:");
  if (suspectRows.length === 0) {
    lines.push("- (none)");
  } else {
    for (const row of suspectRows) {
      lines.push(`- ${row.row_id}  status: ${row.status}  reason: ${firstReasonCode(row)}`);
      lines.push(`  required action: ${defaultRequiredAction(row)}`);
    }
  }

  // Inferred Swift spans (spec 8.2 / 10.2: CI must print inferred spans).
  const inferred = status.rows.flatMap((row) =>
    row.current_bindings
      .filter((binding) => binding.extent_kind === "swift_func_inferred")
      .map((binding) => ({ row_id: row.row_id, binding }))
  );
  if (inferred.length > 0) {
    for (const { row_id, binding } of inferred) {
      lines.push("");
      lines.push("INFERRED SWIFT SPAN");
      lines.push(`row: ${row_id}`);
      lines.push(`binding: ${binding.binding_slug}`);
      lines.push(`file: ${binding.file_path}`);
      lines.push(`span: lines ${binding.span_start_line}-${binding.span_end_line}`);
      lines.push(`span_sha256: ${binding.span_sha256}`);
    }
  }

  return lines.join("\n");
}
