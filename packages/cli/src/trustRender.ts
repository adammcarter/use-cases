// Human-readable renderers for the daily TRUST commands (0.2.0 F4).
//
// `scan`, `verify`, and `impact` are the commands a developer runs constantly to
// answer "is my behaviour coverage still trustworthy?". Their generic key/value
// dump (render.ts `lnEnvelope`) is a raw tree that buries the answer. These
// renderers give each of the three a friendly, at-a-glance human view when the
// user did NOT pass --json.
//
// STRICTLY a rendering layer: it only READS the envelope data each command
// already produced (never recomputes trust), and it is reached ONLY on the
// non-json path (render.ts keeps the --json bytes byte-identical). Output is
// plain ASCII — no ANSI, no TTY requirement — so it renders cleanly when piped.
// The envelope shape is loaded loosely (the CLI loads core's types dynamically),
// so these interfaces mirror only the fields read.

// The command ids these renderers own. Everything else stays on the generic
// dumper (prove / keygen / bind / validate-ledger / …).
export const TRUST_COMMANDS = new Set([
  "markers.scan",
  "markers.verify",
  "markers.impact",
  "markers.recover",
  "showcase.status"
]);

// One line steering the human to the machine-readable form, appended to every
// trust view (kept identical to the generic renderer's footer so existing
// "output contains --json" assertions keep passing).
const JSON_FOOTER = "Add --json for the full machine-readable result envelope.";

// --- shared status vocabulary -------------------------------------------------

type RowStatus = "FRESH" | "SUSPECT" | "UNPROVEN" | "UNBOUND" | "INVALID";
type LocalStatus = "VERIFIED_LOCAL" | "STALE_LOCAL" | "UNVERIFIED_LOCAL" | null;

// A plain-ASCII glyph + word per status. Green states get "✓" (ASCII-safe: it is
// a printable glyph, not an ANSI colour), non-green get "✗" or a neutral "·". No
// colour is ever emitted, so NO_COLOR / piped output is honoured by construction.
function statusBadge(status: RowStatus, localStatus: LocalStatus): { glyph: string; word: string } {
  switch (status) {
    case "FRESH":
      return { glyph: "✓", word: "FRESH" };
    case "SUSPECT":
      return { glyph: "✗", word: "SUSPECT" };
    case "INVALID":
      return { glyph: "✗", word: "INVALID" };
    case "UNPROVEN":
      // A keyless local pass is the daily green light even without a signed proof.
      if (localStatus === "VERIFIED_LOCAL") {
        return { glyph: "✓", word: "VERIFIED_LOCAL" };
      }
      return { glyph: "·", word: "UNPROVEN" };
    case "UNBOUND":
      return { glyph: "·", word: "UNBOUND" };
    default:
      return { glyph: "·", word: String(status) };
  }
}

// True when a row is on the green daily light (nothing to act on).
function isGreen(status: RowStatus, localStatus: LocalStatus): boolean {
  return status === "FRESH" || (status === "UNPROVEN" && localStatus === "VERIFIED_LOCAL");
}

// --- scan ---------------------------------------------------------------------

interface FreshnessRow {
  row_id: string;
  status: RowStatus;
  local_status?: LocalStatus;
  required_action?: string | null;
  required_for_release?: boolean;
}

interface ScanGate {
  blocked: boolean;
  required_bar?: string;
  offending_rows?: Array<{ row_id: string }>;
  // GATE HONESTY (0.2.0): non-required rows below the bar. Present on a passing
  // gate so the human view can warn that drift exists but is NOT enforced.
  ungated_below_bar?: Array<{ row_id: string; status?: string; local_status?: string | null }>;
}

interface IntegrityError {
  code: string;
  row_id?: string;
  binding_slug?: string;
  file_path?: string;
  line?: number;
  message?: string;
  remediation?: string;
}

interface ScanData {
  status: {
    summary: { fresh: number; suspect: number; unproven: number; unbound: number; invalid: number };
    acceptance_claim?: {
      proven: number;
      total: number;
      claimable: boolean;
      statement: string;
    };
    integrity_errors?: IntegrityError[];
    rows: FreshnessRow[];
  };
  gate?: ScanGate;
}

// The action a human should take for a non-green row. Prefer the row's own
// required_action (the core already computes it), but present the daily verb
// `uc recover` for drifted/unverified rows so the fix is one command.
function scanRowAction(row: FreshnessRow): string | null {
  if (isGreen(row.status, row.local_status ?? null)) {
    return null;
  }
  if (row.status === "SUSPECT" || row.status === "UNPROVEN") {
    return `run \`uc recover --row ${row.row_id}\``;
  }
  if (row.status === "INVALID") {
    return "resolve the binding integrity errors, then re-run `uc scan`";
  }
  if (row.status === "UNBOUND") {
    return `bind it with \`uc bind --row ${row.row_id} …\``;
  }
  return row.required_action ? `run \`${row.required_action}\`` : null;
}

function renderScan(data: ScanData): string[] {
  const rows = data.status?.rows ?? [];
  const summary = data.status?.summary ?? { fresh: 0, suspect: 0, unproven: 0, unbound: 0, invalid: 0 };
  const lines: string[] = [];

  // Headline count line, e.g. "3 behaviours: 2 fresh, 1 verified-local". The two
  // GREEN tiers are counted SEPARATELY so the keyless local light is never
  // conflated with the signed FRESH tier: "fresh" means a trusted signed proof,
  // "verified-local" means the keyless local pass (VERIFIED_LOCAL). A keyless
  // green row is therefore NOT counted under "fresh" and NOT under "unproven".
  const total = rows.length;
  const keylessGreen = rows.filter(
    (row) => row.status === "UNPROVEN" && (row.local_status ?? null) === "VERIFIED_LOCAL"
  ).length;
  const unprovenNotGreen = summary.unproven - keylessGreen;
  const parts: string[] = [];
  if (summary.fresh > 0) parts.push(`${summary.fresh} fresh`);
  if (keylessGreen > 0) parts.push(`${keylessGreen} verified-local`);
  if (summary.suspect > 0) parts.push(`${summary.suspect} suspect`);
  if (unprovenNotGreen > 0) parts.push(`${unprovenNotGreen} unproven`);
  if (summary.unbound > 0) parts.push(`${summary.unbound} unbound`);
  if (summary.invalid > 0) parts.push(`${summary.invalid} invalid`);
  const behaviourWord = total === 1 ? "behaviour" : "behaviours";
  lines.push(parts.length > 0 ? `${total} ${behaviourWord}: ${parts.join(", ")}` : `${total} ${behaviourWord}`);

  // State the acceptance conclusion outright, right under the counts. `guard_ok`
  // only means "no policy is blocking" and is green on a matrix where NOTHING is
  // proven — agents have read that as "acceptance green" and nearly claimed it.
  // Say the true thing where they cannot miss it.
  const claim = data.status?.acceptance_claim;
  if (claim) {
    lines.push(
      claim.claimable
        ? `✓ acceptance: ${claim.statement}`
        : `⚠ acceptance: ${claim.statement} — do NOT claim acceptance`
    );
  }
  lines.push("");

  // Per-row line: glyph + status word + row id, then the required action when
  // the row is not green.
  for (const row of rows) {
    const badge = statusBadge(row.status, row.local_status ?? null);
    lines.push(`  ${badge.glyph} ${badge.word.padEnd(9)} ${row.row_id}`);
    const action = scanRowAction(row);
    if (action) {
      lines.push(`      → ${action}`);
    }
  }

  // Integrity errors were JSON-only — the human view never showed them, so a
  // broken registry (a renamed marker, an orphaned row) was invisible unless you
  // reached for --json. Show them, each with the runnable way out.
  const integrityErrors = data.status?.integrity_errors ?? [];
  if (integrityErrors.length > 0) {
    lines.push("");
    const errorWord = integrityErrors.length === 1 ? "error" : "errors";
    lines.push(`integrity ${errorWord} — ${integrityErrors.length}:`);
    for (const error of integrityErrors) {
      const where = [error.file_path, error.line == null ? null : `line ${error.line}`]
        .filter(Boolean)
        .join(" ");
      lines.push(`  ✗ ${error.code}${error.message ? `: ${error.message}` : ""}`);
      if (where) {
        lines.push(`      at ${where}`);
      }
      if (error.remediation) {
        lines.push(`      → ${error.remediation}`);
      }
    }
  }

  // Honour --gate when present: state whether the release/dev bar blocked, and —
  // on a PASS — state HOW MANY required behaviours were evaluated against the bar
  // AND warn about any ungated drift so "gate passed" never reads as endorsing a
  // drifted row that simply lacks required_for_release:true.
  if (data.gate) {
    lines.push("");
    const bar = data.gate.required_bar ?? "?";
    if (data.gate.blocked) {
      const offenders = (data.gate.offending_rows ?? []).map((r) => r.row_id).join(", ");
      lines.push(`✗ gate BLOCKED (bar: ${bar}) — ${offenders}`);
    } else {
      // Count the required behaviours the gate actually evaluated (required rows
      // that met the bar). This is the honest scope of what "passed" covers.
      const requiredMet = rows.filter(
        (row) => row.required_for_release === true && isGreen(row.status, row.local_status ?? null)
      ).length;
      const behaviourWord = requiredMet === 1 ? "behaviour" : "behaviours";
      lines.push(`✓ gate passed — ${requiredMet} required ${behaviourWord} meet ${bar}.`);
    }
    // Warn about EVERY non-required row below the bar (present on pass AND block),
    // naming the single knob that would enforce it. This is what keeps a passing
    // gate from silently endorsing drift.
    const ungated = data.gate.ungated_below_bar ?? [];
    for (const row of ungated) {
      const state = row.status === "UNPROVEN" && (row.local_status ?? null) ? `${row.status}/${row.local_status}` : row.status ?? "below bar";
      lines.push(
        `⚠ ${row.row_id} is ${state} but NOT gated — mark it \`approval_policy.required_for_release: true\` to enforce it.`
      );
    }
  }

  return lines;
}

// --- verify -------------------------------------------------------------------

interface VerifyResult {
  row_id: string;
  status: "pass" | "fail" | "blocked";
}

interface VerifyData {
  results: VerifyResult[];
}

function verifyBadge(status: VerifyResult["status"]): string {
  if (status === "pass") return "✓";
  return "✗";
}

function renderVerify(data: VerifyData): string[] {
  const results = data.results ?? [];
  const lines: string[] = [];

  const passed = results.filter((r) => r.status === "pass").length;
  const failed = results.filter((r) => r.status === "fail").length;
  const blocked = results.filter((r) => r.status === "blocked").length;
  const total = results.length;
  const parts: string[] = [];
  if (passed > 0) parts.push(`${passed} passed`);
  if (failed > 0) parts.push(`${failed} failed`);
  if (blocked > 0) parts.push(`${blocked} blocked`);
  const behaviourWord = total === 1 ? "behaviour" : "behaviours";
  lines.push(
    total === 0
      ? "verify: no bound behaviours to verify"
      : `verify: ${total} ${behaviourWord} — ${parts.join(", ")}`
  );
  lines.push("");

  for (const result of results) {
    lines.push(`  ${verifyBadge(result.status)} ${result.status.toUpperCase().padEnd(7)} ${result.row_id}`);
    if (result.status !== "pass") {
      lines.push(`      → fix the row and re-run \`uc verify --row ${result.row_id}\``);
    }
  }

  return lines;
}

// --- impact -------------------------------------------------------------------

interface ImpactBinding {
  row_id: string;
  binding_slug: string;
  file: string;
}

interface BrokenBinding {
  row_id: string;
  binding_slug: string;
  file: string;
  reason: "deleted" | "renamed";
}

interface ImpactData {
  base?: string;
  impacted?: ImpactBinding[];
  touched?: ImpactBinding[];
  broken_bindings?: BrokenBinding[];
}

function renderImpact(data: ImpactData): string[] {
  const impacted = data.impacted ?? [];
  const touched = data.touched ?? [];
  const broken = data.broken_bindings ?? [];
  const lines: string[] = [];

  // Lead with the UNION of span-hit and file-touched.
  //
  // The headline used to count span overlaps ONLY, so it announced "0 behaviours
  // impacted — nothing impacted" directly above a list of rows sitting on files
  // the change had edited. An agent that reads the headline and stops (which is
  // what headlines are for) skipped re-verifying exactly the rows that needed it.
  // Line-span overlap is a weak proxy for behavioural impact: you can gut a
  // function's semantics from a helper twenty lines below the bound span. Being
  // conservative is the whole job — a false positive costs one re-verify, a false
  // negative ships a regression under a green badge.
  const affected = impacted.length + touched.length;
  const word = affected === 1 ? "behaviour" : "behaviours";
  if (affected === 0) {
    lines.push("0 behaviours impacted by your change");
  } else {
    lines.push(
      `${affected} ${word} may be impacted by your change ` +
        `(${impacted.length} span-hit, ${touched.length} file-touched) — re-verify these`
    );
  }
  if (data.base) {
    lines.push(`(diff base: ${data.base})`);
  }
  lines.push("");

  if (affected === 0) {
    lines.push("  · nothing impacted — no bound span overlaps your change, and no bound file was touched");
  }

  for (const binding of impacted) {
    lines.push(`  ✗ ${binding.row_id}`);
    lines.push(`      → re-verify (span in ${binding.file}); run \`uc verify --row ${binding.row_id}\``);
  }

  // Touched rows are impacted-until-proven-otherwise, so they get the same
  // runnable next command rather than being listed as trivia.
  if (touched.length > 0) {
    lines.push("");
    lines.push(`touched (file changed, span not hit) — ${touched.length}, treat as affected until re-verified:`);
    for (const binding of touched) {
      lines.push(`  ? ${binding.row_id} (${binding.file})`);
      lines.push(`      → re-verify to be sure; run \`uc verify --row ${binding.row_id}\``);
    }
  }

  if (broken.length > 0) {
    lines.push("");
    lines.push(`broken bindings (marked code moved/gone) — ${broken.length}:`);
    for (const binding of broken) {
      lines.push(`  ✗ ${binding.row_id} — ${binding.reason} (${binding.file}); re-bind it`);
    }
  }

  return lines;
}

// --- recover ------------------------------------------------------------------

interface RecoverData {
  recovered?: boolean;
  proved?: boolean;
  target?: string;
  status?: {
    rows?: FreshnessRow[];
  };
}

// A concise human view for `uc recover`: whether it recovered, the target row's
// resulting state (green via VERIFIED_LOCAL / FRESH, or still not green), and a
// next action ONLY when it is still not green. It deliberately does NOT dump the
// raw status envelope (row_hash / span_sha256s / verification_context_hash /
// timestamps) the generic renderer would, and it never headlines "run uc prove"
// when the keyless light is already green — keyless success is a first-class
// green, not a lesser UNPROVEN state.
function renderRecover(data: RecoverData): string[] {
  const rows = data.status?.rows ?? [];
  const target = data.target ?? "the target row";
  const recovered = data.recovered === true;
  const lines: string[] = [];

  // Headline: did recovery restore the row(s) to green?
  if (recovered) {
    lines.push(`✓ recovered ${target} — back to green.`);
  } else {
    lines.push(`✗ could NOT recover ${target} — still not green.`);
  }
  lines.push("");

  // One concise line per row: glyph + state word + row id. For a green row that
  // is the whole story; for a non-green row, add the daily next action.
  for (const row of rows) {
    const badge = statusBadge(row.status, row.local_status ?? null);
    lines.push(`  ${badge.glyph} ${badge.word.padEnd(14)} ${row.row_id}`);
    if (!isGreen(row.status, row.local_status ?? null)) {
      const action = scanRowAction(row);
      if (action) {
        lines.push(`      → ${action}`);
      }
    }
  }

  return lines;
}

// --- showcase approval --------------------------------------------------------

interface ApprovalRequestData {
  approval_request_schema: "ucase-approval-request-v1";
  binding: {
    run_id: string;
    finish_event_id: string;
    plan_content_hash: string;
  };
  jti: string;
  exp: string;
}

interface ShowcaseStatusData {
  run_id: string;
  execution_status: string;
  run_outcome: string;
  approval_state: string;
  approval?: {
    actor_type?: string;
    assurance_tier?: string;
  };
}

function isApprovalRequestData(value: unknown): value is ApprovalRequestData {
  if (value === null || typeof value !== "object") return false;
  const record = value as { approval_request_schema?: unknown; binding?: unknown };
  return record.approval_request_schema === "ucase-approval-request-v1" && record.binding !== null && typeof record.binding === "object";
}

function renderApprovalRequest(data: ApprovalRequestData): string[] {
  return [
    "approval request",
    "",
    `  run ${data.binding.run_id}`,
    `  finish event ${data.binding.finish_event_id}`,
    `  plan ${data.binding.plan_content_hash}`,
    `  nonce ${data.jti}`,
    `  expires ${data.exp}`,
    "",
    "Sign out-of-band:",
    "  uc approve-run --request <request-file> --key-file <out-of-scope-key> --key-id <keyring-key-id> --json"
  ];
}

function renderShowcaseStatus(data: ShowcaseStatusData): string[] {
  const lines = [
    `showcase ${data.run_id}: ${data.execution_status} · ${data.run_outcome}`,
    `approval: ${data.approval_state}`
  ];
  if (data.approval?.actor_type && data.approval.assurance_tier) {
    lines.push(`approved by ${data.approval.actor_type} · tier ${data.approval.assurance_tier}`);
  }
  return lines;
}

export function renderTrustObjectHuman(value: unknown): string | null {
  if (!isApprovalRequestData(value)) {
    return null;
  }
  return `${[...renderApprovalRequest(value), "", JSON_FOOTER].join("\n")}\n`;
}

// --- dispatch -----------------------------------------------------------------

// Render one of the trust commands' human views, or return null so the caller
// falls back to the generic dumper. Returns null when the command is not a trust
// command OR when the payload lacks the command's trust-data shape — the latter
// is how a genuine ERROR envelope (workspace-not-found, bad args: ok:false with
// no status/results/impacted) keeps its generic diagnostics view. A NON-GREEN
// trust result (ok:false but with a real status/results payload) DOES render
// here — that is a normal outcome the human view is meant to show.
export function renderTrustHuman(
  command: string,
  data: unknown,
  ok?: boolean,
  diagnostics?: Array<{ code?: string; severity?: string; message?: string }>,
): string | null {
  if (!TRUST_COMMANDS.has(command) || data === null || typeof data !== "object") {
    return null;
  }
  const d = data as Record<string, unknown>;
  let body: string[];
  switch (command) {
    case "markers.scan":
      if (typeof d.status !== "object" || d.status === null) return null;
      body = renderScan(data as ScanData);
      break;
    case "markers.verify":
      if (!Array.isArray(d.results)) return null;
      body = renderVerify(data as VerifyData);
      break;
    case "markers.impact":
      if (!Array.isArray(d.impacted)) return null;
      body = renderImpact(data as ImpactData);
      break;
    case "markers.recover":
      // A real recover result always carries a boolean `recovered`. An error
      // envelope (workspace-not-found, bad args) does not, so it falls through to
      // the generic diagnostics dumper.
      if (typeof d.recovered !== "boolean") return null;
      body = renderRecover(data as RecoverData);
      break;
    case "showcase.status":
      if (typeof d.run_id !== "string" || typeof d.approval_state !== "string") return null;
      body = renderShowcaseStatus(data as unknown as ShowcaseStatusData);
      break;
    default:
      return null;
  }
  // BLOCKER 2: never let the human view read as unqualified success when the
  // COMMAND failed. Per-row glyphs may be green (a keyless VERIFIED_LOCAL row, or
  // an advisory non-blocking row) while the envelope is ok:false (e.g. scan exit
  // 4 on a rejected proof). A leading failure banner reconciles the framing with
  // the envelope so no green-while-failed slips through. Truthful green (ok:true)
  // and normal non-green outcomes (ok undefined, the pre-0.2.0 default) are
  // unchanged. `exit_code` (when present in data) is surfaced for precision.
  const failed = ok === false;
  const banner = failed ? [failureBanner(command, d)] : [];
  // On failure, surface the envelope's diagnostics (the WHY + the next step).
  // Without this, a failure that carries no status rows — notably `recover`'s
  // verifier-failed path, which returns before it can scan — prints only the
  // headline and leaves the reader with no reason and no action. The generic
  // dumper shows diagnostics; the concise trust view must not lose them.
  const why = failed ? renderDiagnosticLines(diagnostics) : [];
  // Avoid a double blank where a body that already ends in a spacer meets the
  // diagnostics block (which leads with its own spacer).
  const trimmedBody = why.length > 0 && body[body.length - 1] === "" ? body.slice(0, -1) : body;
  const lines = [...banner, ...trimmedBody, ...why, "", JSON_FOOTER];
  return `${lines.join("\n")}\n`;
}

// Diagnostic lines for a failed trust command, in the same glyph vocabulary the
// generic envelope dumper uses so the two views read alike. Empty when there are
// no diagnostics (nothing to add) — the caller only invokes this on failure.
function renderDiagnosticLines(
  diagnostics?: Array<{ code?: string; severity?: string; message?: string }>,
): string[] {
  const usable = (diagnostics ?? []).filter(
    (d) => typeof d?.message === "string" && d.message.length > 0,
  );
  if (usable.length === 0) return [];
  const out: string[] = [""];
  for (const d of usable) {
    const severity = d.severity ?? "info";
    const glyph = severity === "error" ? "✗" : severity === "warning" ? "!" : "·";
    const code = d.code ? `${d.code}: ` : "";
    out.push(`  ${glyph} ${code}${d.message}`);
  }
  return out;
}

// The leading line shown when a trust COMMAND failed (envelope ok:false). Uses
// the same "✗" glyph the non-green rows use, so a reader scanning for failure
// markers sees one at the top regardless of per-row greenness.
function failureBanner(command: string, data: Record<string, unknown>): string {
  const verb = command.startsWith("markers.") ? command.slice("markers.".length) : command;
  const exit = typeof data.exit_code === "number" ? data.exit_code : undefined;
  const suffix = exit !== undefined ? ` (exit ${exit})` : "";
  return `✗ ${verb} FAILED${suffix} — details below; add --json for the machine-readable envelope.\n`;
}
