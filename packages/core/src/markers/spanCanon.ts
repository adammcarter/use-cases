// Span canonicalizer `ucase-span-lines-v2` (spec section 3).
//
// Algorithm (exact):
//   1. Require UTF-8.            (callers pass an already-decoded string)
//   2. Decode as UTF-8.
//   3. Normalize CRLF and CR to LF.
//   4. Select complete lines in the span range.
//   5. Exclude marker lines.     (the scanner passes body lines only)
//   6. Strip trailing spaces and tabs from each selected line.
//   7. Strip the common leading whitespace prefix from every non-empty line.
//   8. Collapse blank-line runs and drop leading/trailing blank lines.
//   9. Preserve comments and relative indentation.
//   10. Join with LF.
//   11. Ensure exactly one trailing LF, unless the canonical body is empty.
//   12. sha256 over UTF-8 bytes.
import { sha256 } from "./canonicalJson.js";

// Normalize CRLF and CR to LF (spec step 3).
export function normalizeNewlines(content: string): string {
  return content.replace(/\r\n/g, "\n").replace(/\r/g, "\n");
}

// Strip trailing spaces and tabs from a single line (spec step 6).
function stripTrailingWs(line: string): string {
  return line.replace(/[ \t]+$/, "");
}

function leadingWs(line: string): string {
  return line.match(/^[ \t]*/)?.[0] ?? "";
}

function commonLeadingWsPrefix(lines: ReadonlyArray<string>): string {
  let prefix: string | undefined;

  for (const line of lines) {
    if (line === "") {
      continue;
    }

    const current = leadingWs(line);
    if (prefix === undefined) {
      prefix = current;
      continue;
    }

    let i = 0;
    while (i < prefix.length && i < current.length && prefix[i] === current[i]) {
      i++;
    }
    prefix = prefix.slice(0, i);

    if (prefix === "") {
      break;
    }
  }

  return prefix ?? "";
}

function collapseBlankLines(lines: ReadonlyArray<string>): string[] {
  const collapsed: string[] = [];

  for (const line of lines) {
    if (line === "") {
      if (collapsed.length > 0 && collapsed[collapsed.length - 1] !== "") {
        collapsed.push("");
      }
      continue;
    }

    collapsed.push(line);
  }

  if (collapsed[collapsed.length - 1] === "") {
    collapsed.pop();
  }

  return collapsed;
}

// Canonicalize the already-selected span body lines.
//
// `lines` are the complete lines strictly between the markers, newline-stripped
// (CR/CRLF already collapsed by line splitting). Cosmetic whole-block reindent,
// blank-line runs and trailing spaces/tabs are ignored while comments and
// relative indentation are preserved. The result joins with LF and carries
// exactly one trailing LF, or is empty when the canonical body has no lines.
export function canonicalizeSpanLines(lines: ReadonlyArray<string>): string {
  const stripped = lines.map(stripTrailingWs);
  const commonPrefix = commonLeadingWsPrefix(stripped);
  const dedented =
    commonPrefix === ""
      ? stripped
      : stripped.map((line) => (line === "" ? line : line.slice(commonPrefix.length)));
  const collapsed = collapseBlankLines(dedented);

  if (collapsed.length === 0) {
    return "";
  }

  return collapsed.join("\n") + "\n";
}

// sha256 over the canonical span bytes, as "sha256:<hex>" (spec step 12).
export function hashSpanLines(lines: ReadonlyArray<string>): string {
  return sha256(canonicalizeSpanLines(lines));
}
