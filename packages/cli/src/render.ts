// Output rendering — the single place that turns a normative result envelope
// into bytes. Both transports through the CLI use it: the legacy dispatcher and
// the declarative command registry. It takes an explicit `json` flag (rather
// than reading module state) so any caller can render correctly without first
// running the legacy path. The `--json` form is byte-identical to the original
// `JSON.stringify(envelope)` output.

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
  return json ? `${JSON.stringify(envelope)}\n` : renderHumanEnvelope(envelope as RenderableEnvelope);
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
