// Renders the `docs/reference/error-codes.md` reference page from the registry.
// Internal (not part of the public export surface) — consumed by the doc-sync
// test and `scripts/generate-error-codes.mjs`.

import { UCM_ERROR_CODES, UCM_ERROR_REGISTRY, type UcmErrorSurface } from "./registry.js";

const SURFACE_TITLES: Record<UcmErrorSurface, string> = {
  marker: "Marker grammar",
  registry: "Binding registry",
  evidence: "Evidence ledger",
  signature: "Signature / proof verification",
  swift: "Swift function recognizer",
  workspace: "Workspace config",
  migration: "Migration",
  showcase: "Showcase lifecycle",
  path: "Path safety"
};

// Stable surface ordering for the document.
const SURFACE_ORDER: UcmErrorSurface[] = [
  "marker",
  "registry",
  "evidence",
  "signature",
  "swift",
  "workspace",
  "migration",
  "showcase",
  "path"
];

function escapeCell(value: string): string {
  return value.replace(/\|/g, "\\|");
}

/** Render the full `error-codes.md` page (with trailing newline). */
export function renderErrorCodesMarkdown(): string {
  const lines: string[] = [];
  lines.push("<!-- GENERATED FILE — do not edit by hand.");
  lines.push(
    "     Regenerate with `node packages/ucm-core/scripts/generate-error-codes.mjs`"
  );
  lines.push("     (source of truth: packages/ucm-core/src/errors/registry.ts). -->");
  lines.push("");
  lines.push("# Error Codes");
  lines.push("");
  lines.push(
    "Stable `UCM_*` error codes are part of the [public API](./stability.md). Each"
  );
  lines.push(
    "code below is a versioned contract: a code is only removed or repurposed in a"
  );
  lines.push(
    "**major** release; new codes ship additively in a **minor**. Diagnostics carry"
  );
  lines.push("the code in their `code` field.");
  lines.push("");
  lines.push(`There are **${UCM_ERROR_CODES.length}** codes across **${SURFACE_ORDER.length}** surfaces.`);
  lines.push("");

  for (const surface of SURFACE_ORDER) {
    const codes = UCM_ERROR_CODES.filter((code) => UCM_ERROR_REGISTRY[code].surface === surface);
    if (codes.length === 0) {
      continue;
    }
    lines.push(`## ${SURFACE_TITLES[surface]}`);
    lines.push("");
    lines.push("| Code | Severity | Message |");
    lines.push("|---|---|---|");
    for (const code of codes) {
      const item = UCM_ERROR_REGISTRY[code];
      lines.push(`| \`${code}\` | ${item.severity} | ${escapeCell(item.message)} |`);
    }
    lines.push("");
  }

  return lines.join("\n");
}
