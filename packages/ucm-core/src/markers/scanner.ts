// Explicit-span scanner (spec sections 2.1, 3, 4.4).
//
// Pure core: given a file path and its contents, find use-case markers, pair
// explicit start/end markers, canonicalize each span, and emit a current
// binding record per matched span (spec 4.4, explicit variant). Every integrity
// problem is reported as a distinct INVALID with a stable error code; nothing is
// best-effort. This phase implements explicit spans only -- a start marker with
// no matching end is rejected as unsupported inference (the Swift recognizer is
// a later phase).
import { sha256 } from "./canonicalJson.js";
import { EXPLICIT_RECOGNIZER_ID, SPAN_CANON_ID } from "./constants.js";
import {
  MarkerErrorCode,
  parseMarkerLine,
  splitSlug,
  type MarkerLineParse
} from "./markerLine.js";
import { canonicalizeSpanLines } from "./spanCanon.js";
import {
  resolveCommentPrefix,
  type CommentPrefixConfig
} from "./commentPrefix.js";

export interface MarkerError {
  code: MarkerErrorCode;
  message: string;
  file_path: string;
  line: number; // 1-based
  slug?: string;
}

// Current binding record, explicit-span variant (spec section 4.4).
export interface CurrentBindingRecord {
  binding_slug: string;
  row_id: string;
  suffix: string | null;
  file_path: string;
  comment_prefix: string;
  extent_kind: "explicit";
  recognizer_id: string;
  span_canon_id: string;
  start_marker: { line: number; column: number };
  end_marker: { line: number; column: number } | null;
  span: {
    start_line: number;
    end_line: number;
    start_byte: number;
    end_byte: number;
    sha256: string;
  };
  diagnostic: { inferred: false };
}

export interface ScanFileResult {
  file_path: string;
  comment_prefix: string | null;
  bindings: CurrentBindingRecord[];
  errors: MarkerError[];
}

export interface ScanResult {
  files: ScanFileResult[];
  bindings: CurrentBindingRecord[];
  errors: MarkerError[];
}

export interface ScannerOptions {
  config?: CommentPrefixConfig;
}

export interface ScanInput {
  file_path: string;
  contents: string;
}

interface PhysicalLine {
  text: string; // line content, terminator excluded
  byteStart: number; // UTF-8 byte offset of the first byte of the line
  byteEnd: number; // UTF-8 byte offset just past the line terminator
}

// Split content into physical lines with UTF-8 byte offsets. Handles LF, CR and
// CRLF terminators; a file ending in a terminator does not yield a trailing
// empty line, while an interior blank line is preserved.
function splitPhysicalLines(content: string): PhysicalLine[] {
  const lines: PhysicalLine[] = [];
  const n = content.length;
  let pos = 0;
  let byteStart = 0;
  while (pos < n) {
    let eol = pos;
    while (eol < n && content[eol] !== "\n" && content[eol] !== "\r") {
      eol += 1;
    }
    const text = content.slice(pos, eol);
    let termLen = 0;
    if (eol < n) {
      termLen = content[eol] === "\r" && content[eol + 1] === "\n" ? 2 : 1;
    }
    const textBytes = Buffer.byteLength(text, "utf8");
    // CR / LF / CRLF are all ASCII, so terminator bytes == terminator length.
    const byteEnd = byteStart + textBytes + termLen;
    lines.push({ text, byteStart, byteEnd });
    byteStart = byteEnd;
    pos = eol + termLen;
  }
  return lines;
}

interface MarkerHit {
  lineIndex: number; // 0-based
  parse: Extract<MarkerLineParse, { kind: "start" | "end" }>;
}

function buildRecord(
  filePath: string,
  commentPrefix: string,
  lines: PhysicalLine[],
  start: MarkerHit,
  end: MarkerHit
): CurrentBindingRecord {
  const slug = start.parse.slug;
  const parts = splitSlug(slug);
  const startIdx = start.lineIndex;
  const endIdx = end.lineIndex;

  // Span body = complete lines strictly between the two marker lines.
  const firstBody = startIdx + 1;
  const lastBody = endIdx - 1;

  let bodyTexts: string[];
  let startLine: number;
  let endLine: number;
  let startByte: number;
  let endByte: number;
  if (firstBody <= lastBody) {
    const body = lines.slice(firstBody, lastBody + 1);
    bodyTexts = body.map((line) => line.text);
    startLine = firstBody + 1;
    endLine = lastBody + 1;
    startByte = body[0].byteStart;
    endByte = body[body.length - 1].byteEnd;
  } else {
    // Empty span body (markers on adjacent lines).
    bodyTexts = [];
    startLine = firstBody + 1;
    endLine = lastBody + 1; // end_line < start_line signals an empty span
    startByte = lines[startIdx].byteEnd;
    endByte = lines[startIdx].byteEnd;
  }

  const canonical = canonicalizeSpanLines(bodyTexts);

  return {
    binding_slug: slug,
    row_id: parts ? parts.row_id : slug,
    suffix: parts ? parts.suffix : null,
    file_path: filePath,
    comment_prefix: commentPrefix,
    extent_kind: "explicit",
    recognizer_id: EXPLICIT_RECOGNIZER_ID,
    span_canon_id: SPAN_CANON_ID,
    start_marker: { line: startIdx + 1, column: start.parse.column },
    end_marker: { line: endIdx + 1, column: end.parse.column },
    span: {
      start_line: startLine,
      end_line: endLine,
      start_byte: startByte,
      end_byte: endByte,
      sha256: sha256(canonical)
    },
    diagnostic: { inferred: false }
  };
}

// Scan a single file's contents for explicit-span markers (pure; no filesystem).
export function scanFileForMarkers(
  filePath: string,
  contents: string,
  options?: ScannerOptions
): ScanFileResult {
  const commentPrefix = resolveCommentPrefix(filePath, options?.config);
  if (commentPrefix === null) {
    // No configured prefix => the file cannot carry markers; skip it.
    return { file_path: filePath, comment_prefix: null, bindings: [], errors: [] };
  }

  const lines = splitPhysicalLines(contents);
  const errors: MarkerError[] = [];
  const bindings: CurrentBindingRecord[] = [];
  const markers: MarkerHit[] = [];

  // Pass 1: parse every line; collect markers and report malformed/forbidden ones.
  for (let i = 0; i < lines.length; i += 1) {
    const parse = parseMarkerLine(lines[i].text, commentPrefix);
    if (parse.kind === "none") {
      continue;
    }
    if (parse.kind === "invalid") {
      errors.push({
        code: parse.code,
        message: parse.message,
        file_path: filePath,
        line: i + 1,
        ...(parse.slug !== undefined ? { slug: parse.slug } : {})
      });
      continue;
    }
    markers.push({ lineIndex: i, parse });
  }

  // Pass 2: duplicate full start-slug detection (spec 1.3 rule 2, within file).
  const seenStart = new Map<string, number>();
  for (const hit of markers) {
    if (hit.parse.kind !== "start") {
      continue;
    }
    const slug = hit.parse.slug;
    if (seenStart.has(slug)) {
      errors.push({
        code: MarkerErrorCode.DUPLICATE_BINDING_SLUG,
        message: `duplicate start marker for slug ${slug} (first at line ${
          (seenStart.get(slug) ?? 0) + 1
        })`,
        file_path: filePath,
        line: hit.lineIndex + 1,
        slug
      });
    } else {
      seenStart.set(slug, hit.lineIndex);
    }
  }

  // Pass 3: pair explicit start/end markers. Nested and overlapping spans are
  // invalid, so at most one span may be open at a time.
  let open: MarkerHit | null = null;
  for (const hit of markers) {
    if (hit.parse.kind === "start") {
      if (open !== null) {
        errors.push({
          code: MarkerErrorCode.NESTED_SPAN,
          message: `nested span: start ${hit.parse.slug} while ${open.parse.slug} is still open (line ${
            open.lineIndex + 1
          })`,
          file_path: filePath,
          line: hit.lineIndex + 1,
          slug: hit.parse.slug
        });
        continue; // keep the outer span open; the inner start is rejected
      }
      open = hit;
      continue;
    }
    // end marker
    if (open === null) {
      errors.push({
        code: MarkerErrorCode.END_WITHOUT_START,
        message: `end marker for ${hit.parse.slug} has no matching start`,
        file_path: filePath,
        line: hit.lineIndex + 1,
        slug: hit.parse.slug
      });
      continue;
    }
    if (hit.parse.slug !== open.parse.slug) {
      errors.push({
        code: MarkerErrorCode.MISMATCHED_END_MARKER,
        message: `end slug ${hit.parse.slug} does not match start slug ${open.parse.slug} (line ${
          open.lineIndex + 1
        })`,
        file_path: filePath,
        line: hit.lineIndex + 1,
        slug: hit.parse.slug
      });
      open = null; // the span is broken; do not emit a binding
      continue;
    }
    bindings.push(buildRecord(filePath, commentPrefix, lines, open, hit));
    open = null;
  }

  // A start with no end is unsupported inference in this phase (no inferred form
  // exists yet); it requires an explicit `end <slug>`.
  if (open !== null) {
    errors.push({
      code: MarkerErrorCode.UNSUPPORTED_INFERENCE,
      message: `start marker for ${open.parse.slug} has no explicit end; unsupported inference, requires explicit end`,
      file_path: filePath,
      line: open.lineIndex + 1,
      slug: open.parse.slug
    });
  }

  return { file_path: filePath, comment_prefix: commentPrefix, bindings, errors };
}

// Scan many files (pure aggregator). Also reports repo-wide duplicate full start
// slugs across files (spec 1.3 rule 2: unique among start markers in the repo).
export function scanFiles(inputs: ReadonlyArray<ScanInput>, options?: ScannerOptions): ScanResult {
  const files = inputs.map((input) =>
    scanFileForMarkers(input.file_path, input.contents, options)
  );

  const bindings = files.flatMap((file) => file.bindings);
  const errors = files.flatMap((file) => file.errors);

  // Cross-file duplicate full start slugs.
  const firstSeen = new Map<string, CurrentBindingRecord>();
  for (const binding of bindings) {
    const prior = firstSeen.get(binding.binding_slug);
    if (prior) {
      errors.push({
        code: MarkerErrorCode.DUPLICATE_BINDING_SLUG,
        message: `duplicate start marker for slug ${binding.binding_slug} across files (first in ${prior.file_path})`,
        file_path: binding.file_path,
        line: binding.start_marker.line,
        slug: binding.binding_slug
      });
    } else {
      firstSeen.set(binding.binding_slug, binding);
    }
  }

  return { files, bindings, errors };
}
