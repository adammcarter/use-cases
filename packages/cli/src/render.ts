// Output rendering — the single place that turns a normative result envelope
// into bytes. Both transports through the CLI use it: the legacy dispatcher and
// the declarative command registry. It takes an explicit `json` flag (rather
// than reading module state) so any caller can render correctly without first
// running the legacy path. The `--json` form is byte-identical to the original
// `JSON.stringify(envelope)` output.

import { renderTrustHuman, renderTrustObjectHuman } from "./trustRender.js";

// Structural shape of the fields the human renderer reads. Kept deliberately
// loose so this module does not depend on core's envelope type (which is loaded
// dynamically at runtime by the CLI).
interface RenderableEnvelope {
  command: string;
  ok?: boolean;
  complete?: boolean;
  data?: unknown;
  diagnostics?: Array<{ code: string; severity?: string; message: string }>;
}

export function renderEnvelope(envelope: unknown, json: boolean): string {
  // The --json form stays BYTE-IDENTICAL to the original `JSON.stringify(envelope)
  // + "\n"` — the human-readable trust view below only ever touches the non-json
  // path (0.2.0 F4).
  if (json) {
    return `${JSON.stringify(envelope)}\n`;
  }
  const trustObject = renderTrustObjectHuman(envelope);
  if (trustObject !== null) {
    return trustObject;
  }
  const record = envelope as RenderableEnvelope;
  // The daily trust commands (scan / verify / impact) get a friendly at-a-glance
  // view — INCLUDING when the trust result is non-green. A `verify` with a failing
  // row, or a SUSPECT/INVALID scan, returns ok:false but that is a NORMAL trust
  // outcome, not an error, and is exactly the case the human view is for. So we do
  // NOT gate on ok: renderTrustHuman returns null for non-trust commands AND for
  // genuine error envelopes (no trust-data shape — e.g. workspace-not-found),
  // which then fall through to the generic diagnostics dumper.
  //
  // Pass the envelope-level ok so the trust view can SURFACE a command failure
  // (BLOCKER 2): the human view must NEVER read as unqualified success when the
  // command failed. Per-row glyphs can legitimately be green (e.g. a keyless
  // VERIFIED_LOCAL row) while the command as a whole FAILED (exit 4) — the banner
  // reconciles the two so the human framing matches the envelope ok.
  const trust = renderTrustHuman(record.command, record.data, record.ok, record.diagnostics);
  if (trust !== null) {
    return trust;
  }
  return renderHumanEnvelope(record);
}

// Render any result envelope as readable text. Because the envelope shape is
// uniform across every command, one renderer covers them all: a status header,
// a YAML-ish view of `data`, then diagnostics — with a pointer to `--json` for
// the machine-readable form.
function renderHumanEnvelope(record: RenderableEnvelope): string {
  const mark = record.ok === true ? "✓" : "✗";
  const head = `${mark} ${record.command}${record.complete === false ? "  (incomplete)" : ""}`;
  const lines: string[] = [head];
  const body = renderHumanValue(record.data, 1);
  if (body.length > 0) {
    lines.push(...body);
  }
  const diagnostics = record.diagnostics ?? [];
  if (diagnostics.length > 0) {
    lines.push("");
    for (const diagnostic of diagnostics) {
      const severity = diagnostic.severity ?? "info";
      const glyph = severity === "error" ? "✗" : severity === "warning" ? "!" : "·";
      lines.push(`  ${glyph} ${diagnostic.code}: ${diagnostic.message}`);
    }
  }
  lines.push("");
  lines.push("Add --json for the full machine-readable result envelope.");
  return `${lines.join("\n")}\n`;
}

function formatScalar(value: unknown): string {
  return typeof value === "string" ? value : String(value);
}

function renderHumanValue(value: unknown, depth: number): string[] {
  const pad = "  ".repeat(depth);
  if (value === null || value === undefined) {
    return [];
  }
  if (Array.isArray(value)) {
    const out: string[] = [];
    for (const item of value) {
      if (item !== null && typeof item === "object") {
        out.push(`${pad}-`);
        out.push(...renderHumanValue(item, depth + 1));
      } else {
        out.push(`${pad}- ${formatScalar(item)}`);
      }
    }
    return out;
  }
  if (typeof value === "object") {
    const out: string[] = [];
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      if (item === null || item === undefined) {
        continue;
      }
      if (Array.isArray(item)) {
        if (item.length === 0) {
          out.push(`${pad}${key}: (none)`);
          continue;
        }
        const allScalar = item.every((entry) => entry === null || typeof entry !== "object");
        if (allScalar) {
          out.push(`${pad}${key}: ${item.map(formatScalar).join(", ")}`);
        } else {
          out.push(`${pad}${key}:`);
          out.push(...renderHumanValue(item, depth + 1));
        }
      } else if (typeof item === "object") {
        out.push(`${pad}${key}:`);
        out.push(...renderHumanValue(item, depth + 1));
      } else {
        out.push(`${pad}${key}: ${formatScalar(item)}`);
      }
    }
    return out;
  }
  return [`${pad}${formatScalar(value)}`];
}
