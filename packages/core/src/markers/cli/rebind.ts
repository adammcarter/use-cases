// `rebind` command core: move a binding to the right declaration.
//
// Re-pointing a binding is ONE intent, so it is one command: the marker moves and
// the registration moves with it, or neither does. Splitting it into unbind then
// bind would open a window where the row is registered to nothing, and a crash in
// that window leaves the matrix claiming a behaviour no code backs.
//
// Why this matters more than it looks: a marker on the wrong declaration is the
// vacuous-row defect in marker form. The row reads as proven while the code it
// points at cannot fail when the claim does, and it looks exactly like a good row
// from every angle `use-cases` reports on. Finding those is the point of reviewing a
// matrix; before this command, a review that found one had nothing to do about it.
import type { ResolvedWorkspaceContext } from "../../roots.js";
import { resolveCommentPrefix, type CommentPrefixConfig } from "../commentPrefix.js";
import { isValidSlug } from "../markerLine.js";
import { validateBindingsJsonl } from "../registry.js";
import { scanFileForMarkers, type CurrentBindingRecord } from "../scanner.js";
import {
  bindingRegisteredEvent,
  bindingReleasedEvent,
  findSlugMarker,
  insertMarkerLines,
  removeMarkerLines,
  type MarkerLocation,
  type MarkerMode
} from "./bindingLifecycle.js";
import { appendJsonlLine, nodeMarkerFs, type MarkerFs } from "./io.js";
import { findRow, loadMarkerRows, resolveUnderRoot, toPosix } from "./shared.js";

export interface RebindCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  rowId: string;
  suffix?: string;
  // The NEW home for the marker, relative to productRoot (or absolute).
  file: string;
  mode: MarkerMode;
  line?: number;
  startLine?: number;
  endLine?: number;
  reason?: string;
  commentPrefix?: string;
  dryRun?: boolean;
  clock: () => string;
  idFactory: () => string;
  version?: string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
}

export interface RebindCommandError {
  code: string;
  message: string;
}

export interface RebindCommandResult {
  exit_code: number;
  ok: boolean;
  command: "rebind";
  row_id: string;
  binding_slug: string;
  // Where the marker ended up.
  file_path: string;
  mode: MarkerMode;
  // Where it came from (null when the marker was already gone from the source).
  moved_from: MarkerLocation | null;
  registry_events_appended: number;
  scan_result?: {
    extent_kind: CurrentBindingRecord["extent_kind"];
    span_start_line: number;
    span_end_line: number;
    span_sha256: string;
  };
  next_command?: string;
  errors: RebindCommandError[];
}

type Base = Pick<RebindCommandResult, "command" | "row_id" | "binding_slug" | "file_path" | "mode">;

function fail(base: Base, exitCode: number, error: RebindCommandError): RebindCommandResult {
  return {
    ...base,
    exit_code: exitCode,
    ok: false,
    moved_from: null,
    registry_events_appended: 0,
    errors: [error]
  };
}

//: @use-case:lifecycle.bindings.rebind_repoints_a_binding
export function runRebindCommand(options: RebindCommandOptions): RebindCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const bindingSlug = options.suffix ? `${options.rowId}#${options.suffix}` : options.rowId;
  const relFile = toPosix(options.file);
  const base: Base = {
    command: "rebind",
    row_id: options.rowId,
    binding_slug: bindingSlug,
    file_path: relFile,
    mode: options.mode
  };

  if (!isValidSlug(bindingSlug)) {
    return fail(base, 3, {
      code: "MALFORMED_MARKER",
      message: `binding slug ${bindingSlug} is not a valid use-case slug`
    });
  }

  const loaded = loadMarkerRows(options.context);
  if (!findRow(loaded.rows, options.rowId)) {
    return fail(base, 2, {
      code: "ROW_NOT_FOUND",
      message: `row ${options.rowId} is not a known use-case row`
    });
  }

  const bindingsText = fs.readText(options.bindingsPath) ?? "";
  const validation = validateBindingsJsonl(bindingsText, loaded.rowIds);
  if (!validation.ok) {
    return fail(base, 4, {
      code: "REGISTRY_INVALID",
      message: `binding registry is not valid: ${validation.errors
        .map((error) => error.message)
        .join("; ")}`
    });
  }
  // Rebind MOVES an existing binding. A row that was never bound has nothing to
  // move, and silently binding it here would make `rebind` a second way to do
  // `bind` — one that skips the "is this row already bound?" question entirely.
  if (!validation.registry.slugToRow.has(bindingSlug)) {
    return fail(base, 2, {
      code: "NOT_REGISTERED",
      message: `binding slug ${bindingSlug} is not registered; bind it first with \`use-cases bind --row ${options.rowId} --file ${relFile} --mode ${options.mode}\``
    });
  }

  // 1. Locate the current marker anywhere in the product tree.
  const found = findSlugMarker({
    fs,
    productRoot: options.productRoot,
    slug: bindingSlug,
    commentConfig: options.commentConfig,
    skipPaths: [options.context.data_root]
  });

  // 2. Compute both edits IN MEMORY before writing anything. When the old and new
  //    markers share a file, the insertion must land on the contents with the old
  //    marker already removed — otherwise the caller's line numbers, which they
  //    read off the file as it will look afterwards, are off by the marker lines.
  const sameFile = found !== null && found.location.file_path === relFile;
  const removedContents = found ? removeMarkerLines(found.contents, found.location) : null;

  const absTarget = resolveUnderRoot(options.productRoot, options.file);
  const targetBefore = sameFile ? (removedContents as string) : fs.readText(absTarget);
  if (targetBefore === null) {
    return fail(base, 2, {
      code: "FILE_NOT_FOUND",
      message: `source file ${relFile} does not exist`
    });
  }

  const commentPrefix =
    options.commentPrefix ?? resolveCommentPrefix(relFile, options.commentConfig, targetBefore);
  if (commentPrefix === null || commentPrefix === undefined) {
    return fail(base, 2, {
      code: "NO_COMMENT_PREFIX",
      message: `no comment prefix is configured for ${relFile}; pass --comment-prefix`
    });
  }

  const edit = insertMarkerLines(targetBefore, commentPrefix, bindingSlug, {
    mode: options.mode,
    line: options.line,
    startLine: options.startLine,
    endLine: options.endLine
  });
  if ("error" in edit) {
    return fail(base, 2, edit.error);
  }

  // 3. Validate the NEW placement by scanning it, exactly as bind does. A target
  //    that cannot resolve to a span aborts with both halves untouched, so a
  //    failed rebind costs nothing and the row stays bound where it was.
  const scan = scanFileForMarkers(relFile, edit.contents, { config: options.commentConfig });
  const matching = scan.bindings.find((binding) => binding.binding_slug === bindingSlug);
  const slugError = scan.errors.find((error) => error.slug === bindingSlug);
  if (slugError || !matching) {
    return fail(base, 3, {
      code: slugError ? slugError.code : "MARKER_NOT_RESOLVED",
      message: slugError
        ? slugError.message
        : `the placed marker for ${bindingSlug} did not resolve to a valid span`
    });
  }

  const scanResult = {
    extent_kind: matching.extent_kind,
    span_start_line: matching.span.start_line,
    span_end_line: matching.span.end_line,
    span_sha256: matching.span.sha256
  };

  if (options.dryRun) {
    return {
      ...base,
      exit_code: 0,
      ok: true,
      moved_from: found ? found.location : null,
      registry_events_appended: 0,
      scan_result: scanResult,
      errors: []
    };
  }

  // 4. Commit: source first, then release, then re-register. Ordered so that any
  //    interruption leaves a state the tool can still describe and recover.
  if (found && !sameFile) {
    fs.writeText(
      resolveUnderRoot(options.productRoot, found.location.file_path),
      removedContents as string,
      { preserveMode: true }
    );
  }
  fs.writeText(absTarget, edit.contents, { preserveMode: true });

  const reason = options.reason ?? "rebind";
  appendJsonlLine(
    fs,
    options.bindingsPath,
    JSON.stringify(
      bindingReleasedEvent({
        command: "rebind",
        rowId: options.rowId,
        bindingSlug,
        reason,
        eventId: options.idFactory(),
        createdAt: options.clock(),
        version: options.version
      })
    )
  );
  appendJsonlLine(
    fs,
    options.bindingsPath,
    JSON.stringify(
      bindingRegisteredEvent({
        command: "rebind",
        rowId: options.rowId,
        bindingSlug,
        reason,
        eventId: options.idFactory(),
        createdAt: options.clock(),
        version: options.version
      })
    )
  );

  return {
    ...base,
    exit_code: 0,
    ok: true,
    moved_from: found ? found.location : null,
    registry_events_appended: 2,
    scan_result: scanResult,
    // The row's old proof does not survive the move (the binding set it was
    // proven against no longer exists), so re-verification is the next step.
    next_command: `use-cases verify --row ${options.rowId}`,
    errors: []
  };
}
//: @use-case:end lifecycle.bindings.rebind_repoints_a_binding
