// Shared marker-editing and registry-event plumbing for the three commands that
// write a binding: bind (place + register), unbind (remove + release), and rebind
// (move + release + re-register).
//
// It lives in one place on purpose. `use-cases` refuses a hand-placed marker and a
// hand-edited ledger, and those refusals are only fair while the tool itself is
// the single writer of BOTH halves — the marker in the source and the event in
// `bindings.jsonl`. Two implementations of "move a marker" would be two chances
// to move one half without the other.
import { BINDING_REGISTRY_SCHEMA_ID } from "../constants.js";
import { parseMarkerLine } from "../markerLine.js";
import { UCM_VERSION } from "../../version.js";
import type { MarkerFs } from "./io.js";
import { collectSourceInputs, toPosix } from "./shared.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import { resolveCommentPrefix } from "../commentPrefix.js";

export type MarkerMode = "explicit" | "swift-func";

// Where a marker should go: a single declaration line (swift-func, marker goes
// immediately before it) or an inclusive span (explicit, a marker on each side).
export interface MarkerPlacement {
  mode: MarkerMode;
  line?: number;
  startLine?: number;
  endLine?: number;
}

export interface MarkerEditError {
  code: string;
  message: string;
}

// One marker occurrence in one file. `end_line` is null for a lone start marker
// (a Swift inferred span), which has no closing marker to remove.
export interface MarkerLocation {
  file_path: string;
  start_line: number;
  end_line: number | null;
}

export type InsertResult = { contents: string } | { error: MarkerEditError };

// Split into logical lines, remembering whether the file ended with a newline so
// an edit does not silently add or remove the trailing terminator.
function splitKeepingTerminator(source: string): { lines: string[]; terminator: boolean } {
  if (source === "") {
    return { lines: [], terminator: false };
  }
  const terminator = source.endsWith("\n");
  const body = terminator ? source.slice(0, -1) : source;
  return { lines: body.split("\n"), terminator };
}

function joinWithTerminator(lines: string[], terminator: boolean): string {
  const joined = lines.join("\n");
  return terminator ? `${joined}\n` : joined;
}

// Insert the marker(s) for `slug` into `source` at `placement`.
export function insertMarkerLines(
  source: string,
  commentPrefix: string,
  slug: string,
  placement: MarkerPlacement
): InsertResult {
  const { lines, terminator } = splitKeepingTerminator(source);
  const marker = `${commentPrefix}: @use-case:${slug}`;

  if (placement.mode === "swift-func") {
    if (placement.line === undefined || placement.line < 1) {
      return { error: { code: "BIND_LINE_REQUIRED", message: "--line is required for swift-func bind" } };
    }
    const insertAt = placement.line - 1;
    if (insertAt > lines.length) {
      return {
        error: { code: "BIND_LINE_OUT_OF_RANGE", message: `--line ${placement.line} is past end of file` }
      };
    }
    lines.splice(insertAt, 0, marker);
    return { contents: joinWithTerminator(lines, terminator) };
  }

  if (placement.startLine === undefined || placement.endLine === undefined) {
    return {
      error: {
        code: "BIND_SPAN_REQUIRED",
        message: "--start-line and --end-line are required for explicit bind"
      }
    };
  }
  if (
    placement.startLine < 1 ||
    placement.endLine < placement.startLine ||
    placement.endLine > lines.length
  ) {
    return {
      error: {
        code: "BIND_SPAN_OUT_OF_RANGE",
        message: `explicit span ${placement.startLine}-${placement.endLine} is out of range`
      }
    };
  }
  const endMarker = `${commentPrefix}: @use-case:end ${slug}`;
  // Insert end first (higher index) so the start insertion does not shift it.
  lines.splice(placement.endLine, 0, endMarker);
  lines.splice(placement.startLine - 1, 0, marker);
  return { contents: joinWithTerminator(lines, terminator) };
}

// Find `slug`'s marker lines in one file's contents.
//
// This reads the raw lines rather than the scanner's binding records on purpose:
// a marker whose span is BROKEN (the declaration after it is not a func, say)
// produces no binding record, and that is exactly the state someone needs to
// release themselves from.
export function locateMarkerLines(
  filePath: string,
  contents: string,
  commentPrefix: string,
  slug: string
): MarkerLocation | null {
  const { lines } = splitKeepingTerminator(contents);
  let startIndex: number | null = null;
  let endIndex: number | null = null;
  for (let i = 0; i < lines.length; i += 1) {
    const parse = parseMarkerLine(lines[i], commentPrefix);
    if (parse.kind === "start" && parse.slug === slug && startIndex === null) {
      startIndex = i;
      continue;
    }
    if (parse.kind === "end" && parse.slug === slug && startIndex !== null && endIndex === null) {
      endIndex = i;
    }
  }
  if (startIndex === null) {
    return null;
  }
  return {
    file_path: filePath,
    start_line: startIndex + 1,
    end_line: endIndex === null ? null : endIndex + 1
  };
}

// Remove the marker line(s) named by `location` from `contents`.
export function removeMarkerLines(contents: string, location: MarkerLocation): string {
  const { lines, terminator } = splitKeepingTerminator(contents);
  const drop = new Set<number>([location.start_line - 1]);
  if (location.end_line !== null) {
    drop.add(location.end_line - 1);
  }
  return joinWithTerminator(
    lines.filter((_line, index) => !drop.has(index)),
    terminator
  );
}

export interface FindSlugMarkerOptions {
  fs: MarkerFs;
  productRoot: string;
  slug: string;
  commentConfig?: CommentPrefixConfig;
  skipPaths?: string[];
}

// A slug's marker, wherever it is in the product tree, with the file's contents.
// Returns null when no marker for the slug exists (already removed by hand).
export function findSlugMarker(
  options: FindSlugMarkerOptions
): { location: MarkerLocation; contents: string; commentPrefix: string } | null {
  const inputs = collectSourceInputs(options.productRoot, {
    fs: options.fs,
    config: options.commentConfig,
    skipPaths: options.skipPaths
  });
  for (const input of inputs) {
    const commentPrefix = resolveCommentPrefix(input.file_path, options.commentConfig, input.contents);
    if (commentPrefix === null || commentPrefix === undefined) {
      continue;
    }
    const location = locateMarkerLines(
      toPosix(input.file_path),
      input.contents,
      commentPrefix,
      options.slug
    );
    if (location) {
      return { location, contents: input.contents, commentPrefix };
    }
  }
  return null;
}

export interface RegistryEventInput {
  command: string;
  rowId: string;
  bindingSlug: string;
  reason: string;
  eventId: string;
  createdAt: string;
  version?: string;
}

function registryEvent(
  eventType: "binding_registered" | "binding_released",
  input: RegistryEventInput
): Record<string, unknown> {
  return {
    schema: BINDING_REGISTRY_SCHEMA_ID,
    event_type: eventType,
    event_id: input.eventId,
    created_at: input.createdAt,
    created_by: {
      tool: "use-cases",
      command: input.command,
      version: input.version ?? UCM_VERSION
    },
    row_id: input.rowId,
    binding_slug: input.bindingSlug,
    reason: input.reason
  };
}

export function bindingRegisteredEvent(input: RegistryEventInput): Record<string, unknown> {
  return registryEvent("binding_registered", input);
}

// The event that ENDS a registration. Appended, never a deletion, so the ledger
// stays append-only while the binding becomes re-pointable.
export function bindingReleasedEvent(input: RegistryEventInput): Record<string, unknown> {
  return registryEvent("binding_released", input);
}
