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
export const TRUST_COMMANDS = new Set(["markers.scan", "markers.verify", "markers.impact"]);

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
}

interface ScanGate {
  blocked: boolean;
  required_bar?: string;
  offending_rows?: Array<{ row_id: string }>;
}

interface ScanData {
  status: {
    summary: { fresh: number; suspect: number; unproven: number; unbound: number; invalid: number };
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

  // Headline count line, e.g. "3 behaviours: 2 fresh, 1 suspect". "fresh" here is
  // the daily GREEN light (FRESH proof OR keyless VERIFIED_LOCAL); a keyless
  // green row is therefore NOT double-counted under "unproven".
  const total = rows.length;
  const green = rows.filter((row) => isGreen(row.status, row.local_status ?? null)).length;
  const keylessGreen = rows.filter(
    (row) => row.status === "UNPROVEN" && (row.local_status ?? null) === "VERIFIED_LOCAL"
  ).length;
  const unprovenNotGreen = summary.unproven - keylessGreen;
  const parts: string[] = [];
  if (green > 0) parts.push(`${green} fresh`);
  if (summary.suspect > 0) parts.push(`${summary.suspect} suspect`);
  if (unprovenNotGreen > 0) parts.push(`${unprovenNotGreen} unproven`);
  if (summary.unbound > 0) parts.push(`${summary.unbound} unbound`);
  if (summary.invalid > 0) parts.push(`${summary.invalid} invalid`);
  const behaviourWord = total === 1 ? "behaviour" : "behaviours";
  lines.push(parts.length > 0 ? `${total} ${behaviourWord}: ${parts.join(", ")}` : `${total} ${behaviourWord}`);
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

  // Honour --gate when present: state whether the release/dev bar blocked.
  if (data.gate) {
    lines.push("");
    if (data.gate.blocked) {
      const offenders = (data.gate.offending_rows ?? []).map((r) => r.row_id).join(", ");
      lines.push(`✗ gate BLOCKED (bar: ${data.gate.required_bar ?? "?"}) — ${offenders}`);
    } else {
      lines.push(`✓ gate passed (bar: ${data.gate.required_bar ?? "?"})`);
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

  const word = impacted.length === 1 ? "behaviour" : "behaviours";
  lines.push(`${impacted.length} ${word} impacted by your change`);
  if (data.base) {
    lines.push(`(diff base: ${data.base})`);
  }
  lines.push("");

  if (impacted.length === 0) {
    lines.push("  · nothing impacted — no bound span overlaps your change");
  } else {
    for (const binding of impacted) {
      lines.push(`  ✗ ${binding.row_id}`);
      lines.push(`      → re-verify (span in ${binding.file}); run \`uc verify --row ${binding.row_id}\``);
    }
  }

  if (touched.length > 0) {
    lines.push("");
    lines.push(`touched (file changed, span not hit) — ${touched.length}:`);
    for (const binding of touched) {
      lines.push(`  · ${binding.row_id} (${binding.file})`);
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

// --- dispatch -----------------------------------------------------------------

// Render one of the trust commands' human views, or return null so the caller
// falls back to the generic dumper. Returns null when the command is not a trust
// command OR when the payload lacks the command's trust-data shape — the latter
// is how a genuine ERROR envelope (workspace-not-found, bad args: ok:false with
// no status/results/impacted) keeps its generic diagnostics view. A NON-GREEN
// trust result (ok:false but with a real status/results payload) DOES render
// here — that is a normal outcome the human view is meant to show.
export function renderTrustHuman(command: string, data: unknown, ok?: boolean): string | null {
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
  const lines = [...banner, ...body, "", JSON_FOOTER];
  return `${lines.join("\n")}\n`;
}

// The leading line shown when a trust COMMAND failed (envelope ok:false). Uses
// the same "✗" glyph the non-green rows use, so a reader scanning for failure
// markers sees one at the top regardless of per-row greenness.
function failureBanner(command: string, data: Record<string, unknown>): string {
  const verb = command.slice("markers.".length);
  const exit = typeof data.exit_code === "number" ? data.exit_code : undefined;
  const suffix = exit !== undefined ? ` (exit ${exit})` : "";
  return `✗ ${verb} FAILED${suffix} — see the rows below; add --json for the machine-readable envelope.\n`;
}
