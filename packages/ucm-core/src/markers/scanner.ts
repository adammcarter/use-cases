// Explicit-span scanner + Swift inferred-span wiring (spec sections 2, 3, 4.4, 9).
//
// Pure core: given a file path and its contents, find use-case markers, pair
// explicit start/end markers, canonicalize each span, and emit a current
// binding record per matched span (spec 4.4). Every integrity problem is
// reported as a distinct INVALID with a stable error code; nothing is
// best-effort.
//
// A start marker with no explicit end is resolved as follows:
//   * Swift file (`//` prefix, `.swift`)  -> the Swift function recognizer
//     (spec section 9). It either proves an inferred span (extent_kind
//     "swift_func_inferred") or fails closed with a 9.4 code.
//   * any other file                       -> UNSUPPORTED_INFERENCE (spec 2.1
//     rule 5). Explicit end always wins (spec 2.1 rule 6).
import { sha256 } from "./canonicalJson.js";
import {
  EXPLICIT_RECOGNIZER_ID,
  SPAN_CANON_ID,
  SWIFT_FUNC_RECOGNIZER_ID
} from "./constants.js";
import {
  MarkerErrorCode,
  parseMarkerLine,
  splitSlug,
  type MarkerLineParse
} from "./markerLine.js";
import { canonicalizeSpanLines } from "./spanCanon.js";
import {
  fileExtension,
  resolveCommentPrefix,
  type CommentPrefixConfig
} from "./commentPrefix.js";
import { splitPhysicalLines, type PhysicalLine } from "./physicalLines.js";
import {
  recognizeSwiftFuncSpan,
  SwiftFuncErrorCode
} from "./swiftFuncRecognizer.js";

// A marker / span error code is either a marker-pairing code or a Swift
// recognizer (9.4) code; every one denotes an INVALID condition.
export type ScanErrorCode = MarkerErrorCode | SwiftFuncErrorCode;

export interface MarkerError {
  code: ScanErrorCode;
  message: string;
  file_path: string;
  line: number; // 1-based
  slug?: string;
}

export interface ExplicitBindingDiagnostic {
  inferred: false;
}

export interface InferredBindingDiagnostic {
  symbol_kind: "swift_func";
  symbol_name: string;
  inferred: true;
}

// Current binding record (spec section 4.4), explicit or inferred variant.
export interface CurrentBindingRecord {
  binding_slug: string;
  row_id: string;
  suffix: string | null;
  file_path: string;
  comment_prefix: string;
  extent_kind: "explicit" | "swift_func_inferred";
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
  diagnostic: ExplicitBindingDiagnostic | InferredBindingDiagnostic;
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

interface MarkerHit {
  lineIndex: number; // 0-based
  parse: Extract<MarkerLineParse, { kind: "start" | "end" }>;
}

function buildExplicitRecord(
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

// Resolve a lone start marker (no explicit end). Swift files go through the
// function recognizer; everything else is unsupported inference. Returns either
// an inferred binding record or a MarkerError (fail-closed).
function resolveLoneStart(
  filePath: string,
  commentPrefix: string,
  contents: string,
  lines: PhysicalLine[],
  start: MarkerHit
): { binding?: CurrentBindingRecord; error?: MarkerError } {
  const slug = start.parse.slug;
  const isSwift = commentPrefix === "//" && fileExtension(filePath) === ".swift";

  if (!isSwift) {
    return {
      error: {
        code: MarkerErrorCode.UNSUPPORTED_INFERENCE,
        message: `start marker for ${slug} has no explicit end; inferred end is only supported for Swift func, requires explicit end`,
        file_path: filePath,
        line: start.lineIndex + 1,
        slug
      }
    };
  }

  const result = recognizeSwiftFuncSpan(contents, start.lineIndex, {
    markerCommentPrefix: commentPrefix
  });
  if (!result.ok) {
    return {
      error: {
        code: result.code,
        message: `${result.message}; fix: add an explicit "${commentPrefix}: @use-case: end ${slug}" or move the marker`,
        file_path: filePath,
        line: start.lineIndex + 1,
        slug
      }
    };
  }

  const parts = splitSlug(slug);
  const canonical = canonicalizeSpanLines(result.body_lines);
  return {
    binding: {
      binding_slug: slug,
      row_id: parts ? parts.row_id : slug,
      suffix: parts ? parts.suffix : null,
      file_path: filePath,
      comment_prefix: commentPrefix,
      extent_kind: "swift_func_inferred",
      recognizer_id: SWIFT_FUNC_RECOGNIZER_ID,
      span_canon_id: SPAN_CANON_ID,
      start_marker: { line: start.lineIndex + 1, column: start.parse.column },
      end_marker: null,
      span: {
        start_line: result.span.start_line,
        end_line: result.span.end_line,
        start_byte: result.span.start_byte,
        end_byte: result.span.end_byte,
        sha256: sha256(canonical)
      },
      diagnostic: {
        symbol_kind: "swift_func",
        symbol_name: result.symbol_name,
        inferred: true
      }
    }
  };
}

// Scan a single file's contents for markers (pure; no filesystem).
export function scanFileForMarkers(
  filePath: string,
  contents: string,
  options?: ScannerOptions
): ScanFileResult {
  const commentPrefix = resolveCommentPrefix(filePath, options?.config, contents);
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

  // Pass 3: pair explicit start/end markers with a stack. Nested and overlapping
  // spans are invalid in v1, so a matched end that leaves another span open is a
  // NESTED_SPAN and suppresses every involved binding. Starts that are never
  // closed are lone starts -> inference candidates.
  const stack: MarkerHit[] = [];
  const tainted = new Set<MarkerHit>();
  const explicitPairs: Array<{ start: MarkerHit; end: MarkerHit }> = [];
  for (const hit of markers) {
    if (hit.parse.kind === "start") {
      stack.push(hit);
      continue;
    }
    // end marker
    const startHit = stack.pop();
    if (startHit === undefined) {
      errors.push({
        code: MarkerErrorCode.END_WITHOUT_START,
        message: `end marker for ${hit.parse.slug} has no matching start`,
        file_path: filePath,
        line: hit.lineIndex + 1,
        slug: hit.parse.slug
      });
      continue;
    }
    if (startHit.parse.slug !== hit.parse.slug) {
      errors.push({
        code: MarkerErrorCode.MISMATCHED_END_MARKER,
        message: `end slug ${hit.parse.slug} does not match start slug ${startHit.parse.slug} (line ${
          startHit.lineIndex + 1
        })`,
        file_path: filePath,
        line: hit.lineIndex + 1,
        slug: hit.parse.slug
      });
      continue; // span broken; do not emit a binding
    }
    if (stack.length > 0) {
      // The just-closed span sits inside another still-open span.
      errors.push({
        code: MarkerErrorCode.NESTED_SPAN,
        message: `nested span: ${hit.parse.slug} closes inside ${
          stack[stack.length - 1].parse.slug
        } (line ${stack[stack.length - 1].lineIndex + 1})`,
        file_path: filePath,
        line: hit.lineIndex + 1,
        slug: hit.parse.slug
      });
      tainted.add(startHit);
      for (const open of stack) {
        tainted.add(open);
      }
      continue;
    }
    if (tainted.has(startHit)) {
      continue; // container of a nested span; binding suppressed
    }
    explicitPairs.push({ start: startHit, end: hit });
  }

  for (const pair of explicitPairs) {
    bindings.push(buildExplicitRecord(filePath, commentPrefix, lines, pair.start, pair.end));
  }

  // Pass 4: lone (unclosed) start markers -> Swift inference or unsupported.
  for (const lone of stack) {
    const { binding, error } = resolveLoneStart(filePath, commentPrefix, contents, lines, lone);
    if (binding) {
      bindings.push(binding);
    }
    if (error) {
      errors.push(error);
    }
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

// Format the spec 8.2 "INFERRED SWIFT SPAN" CI report block for an inferred
// binding record. Returns null for explicit bindings (nothing to print).
export function formatInferredSwiftSpanReport(binding: CurrentBindingRecord): string | null {
  if (binding.extent_kind !== "swift_func_inferred" || !binding.diagnostic.inferred) {
    return null;
  }
  return [
    "INFERRED SWIFT SPAN",
    `row: ${binding.row_id}`,
    `binding: ${binding.binding_slug}`,
    `file: ${binding.file_path}`,
    `symbol: ${binding.diagnostic.symbol_name}`,
    `span: lines ${binding.span.start_line}-${binding.span.end_line}`,
    `span_sha256: ${binding.span.sha256}`
  ].join("\n");
}
