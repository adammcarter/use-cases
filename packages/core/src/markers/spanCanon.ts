// Span canonicalizer `ucase-span-lines-v1` (spec section 3).
//
// Algorithm (exact):
//   1. Require UTF-8.            (callers pass an already-decoded string)
//   2. Decode as UTF-8.
//   3. Normalize CRLF and CR to LF.
//   4. Select complete lines in the span range.
//   5. Exclude marker lines.     (the scanner passes body lines only)
//   6. Strip trailing spaces and tabs from each selected line.
//   7. Preserve leading whitespace.
//   8. Preserve comments.
//   9. Preserve blank lines.
//   10. Join with LF.
//   11. Ensure exactly one trailing LF.
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

// Canonicalize the already-selected span body lines.
//
// `lines` are the complete lines strictly between the markers, newline-stripped
// (CR/CRLF already collapsed by line splitting). Leading whitespace, comments
// and blank lines are preserved; only trailing spaces/tabs are removed. The
// result joins with LF and carries exactly one trailing LF, or is empty when the
// span body has no lines.
export function canonicalizeSpanLines(lines: ReadonlyArray<string>): string {
  if (lines.length === 0) {
    return "";
  }
  return lines.map(stripTrailingWs).join("\n") + "\n";
}

// sha256 over the canonical span bytes, as "sha256:<hex>" (spec step 12).
export function hashSpanLines(lines: ReadonlyArray<string>): string {
  return sha256(canonicalizeSpanLines(lines));
}
