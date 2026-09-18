// `bind` command core (spec 8.1; Phase 7).
//
// Places/registers an identity-only marker and appends ONE binding_registered
// event to the append-only registry — but only after the resulting source edit
// scans clean (transactional rule, spec 8.1). It never writes evidence, never
// emits proofs, and never accepts caller-supplied hashes (it accepts a row id, a
// file, and a placement only). Exit codes follow spec 8.1 (0/2/3/4).
import type { ResolvedWorkspaceContext } from "../../roots.js";
import {
  resolveCommentPrefix,
  type CommentPrefixConfig
} from "../commentPrefix.js";
import { bindingRegisteredEvent, insertMarkerLines } from "./bindingLifecycle.js";
import { isValidSlug } from "../markerLine.js";
import { validateBindingsJsonl } from "../registry.js";
import {
  scanFileForMarkers,
  type CurrentBindingRecord
} from "../scanner.js";
import { appendJsonlLine, nodeMarkerFs, type MarkerFs } from "./io.js";
import { findRow, loadMarkerRows, resolveUnderRoot, toPosix } from "./shared.js";

export type BindMode = "explicit" | "swift-func";

export interface BindCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  rowId: string;
  suffix?: string;
  // Path to the source file, relative to productRoot (or absolute).
  file: string;
  mode: BindMode;
  // swift-func: 1-based line of the first declaration token (marker is inserted
  // immediately before it). explicit: the inclusive span line range.
  line?: number;
  startLine?: number;
  endLine?: number;
  commentPrefix?: string;
  // Register a marker the caller already placed (no source edit).
  registerExisting?: boolean;
  dryRun?: boolean;
  clock: () => string;
  idFactory: () => string;
  version?: string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
}

export interface BindCommandError {
  code: string;
  message: string;
}

export interface BindCommandResult {
  exit_code: number;
  ok: boolean;
  command: "bind";
  row_id: string;
  binding_slug: string;
  file_path: string;
  mode: BindMode;
  registry_event_appended: boolean;
  scan_result?: {
    extent_kind: CurrentBindingRecord["extent_kind"];
    span_start_line: number;
    span_end_line: number;
    span_sha256: string;
  };
  // Binding succeeds and FEELS like progress, so rows get bound and then left
  // UNPROVEN forever ("all 7 of my rows are in exactly that state right now").
  // A successful bind now ends by naming the command that actually proves the row.
  next_command?: string;
  errors: BindCommandError[];
}

function fail(
  base: Omit<BindCommandResult, "exit_code" | "ok" | "registry_event_appended" | "errors" | "scan_result">,
  exitCode: number,
  error: BindCommandError
): BindCommandResult {
  return {
    ...base,
    exit_code: exitCode,
    ok: false,
    registry_event_appended: false,
    errors: [error]
  };
}

//: @use-case:lifecycle.signals.bind_names_the_next_step
export function runBindCommand(options: BindCommandOptions): BindCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const bindingSlug = options.suffix ? `${options.rowId}#${options.suffix}` : options.rowId;
  const relFile = toPosix(options.file);
  const base = {
    command: "bind" as const,
    row_id: options.rowId,
    binding_slug: bindingSlug,
    file_path: relFile,
    mode: options.mode
  };

  // 1. Slug grammar (identity only; spec 1.3).
  if (!isValidSlug(bindingSlug)) {
    return fail(base, 3, {
      code: "MALFORMED_MARKER",
      message: `binding slug ${bindingSlug} is not a valid use-case slug`
    });
  }

  // 2. Row must exist.
  const loaded = loadMarkerRows(options.context);
  if (!findRow(loaded.rows, options.rowId)) {
    return fail(base, 2, {
      code: "ROW_NOT_FOUND",
      message: `row ${options.rowId} is not a known use-case row`
    });
  }

  // 3. Read the source first so the comment prefix can be resolved from a
  //    shebang for extensionless scripts, then resolve the prefix.
  const absFile = resolveUnderRoot(options.productRoot, options.file);
  const current = fs.readText(absFile);
  if (current === null) {
    return fail(base, 2, {
      code: "FILE_NOT_FOUND",
      message: `source file ${relFile} does not exist`
    });
  }
  const commentPrefix = options.commentPrefix ?? resolveCommentPrefix(relFile, options.commentConfig, current);
  if (commentPrefix === null || commentPrefix === undefined) {
    return fail(base, 2, {
      code: "NO_COMMENT_PREFIX",
      message: `no comment prefix is configured for ${relFile}; pass --comment-prefix`
    });
  }

  // 4. Registry pre-checks (append-only log must already be valid).
  const bindingsText = fs.readText(options.bindingsPath) ?? "";
  const registryValidation = validateBindingsJsonl(bindingsText, loaded.rowIds);
  if (!registryValidation.ok) {
    return fail(base, 4, {
      code: "REGISTRY_INVALID",
      message: `binding registry is not valid: ${registryValidation.errors
        .map((error) => error.message)
        .join("; ")}`
    });
  }
  if (registryValidation.registry.slugToRow.has(bindingSlug)) {
    // Naming the way out matters more here than anywhere else: this refusal is
    // what a wrongly-placed binding hits on the way back in, and without the
    // hint it reads as "this row can never be corrected".
    return fail(base, 4, {
      code: "DUPLICATE_REGISTRATION",
      message:
        `binding slug ${bindingSlug} is already registered; ` +
        `re-point it with \`use-cases rebind --row ${options.rowId} --file <file> --mode <mode>\` ` +
        `or release it with \`use-cases unbind --row ${options.rowId}\``
    });
  }

  // 5. Compute the new source (or use existing for --register-existing).
  //    `current`/`absFile` were read above so the prefix could honour a shebang.

  let nextContents: string;
  if (options.registerExisting) {
    nextContents = current;
  } else {
    const edit = insertMarkerLines(current, commentPrefix, bindingSlug, {
      mode: options.mode,
      line: options.line,
      startLine: options.startLine,
      endLine: options.endLine
    });
    if ("error" in edit) {
      return fail(base, 2, edit.error);
    }
    nextContents = edit.contents;
  }

  // 6. Validate the resulting marker by scanning the affected file (spec 8.1
  // steps 7/8). Fail closed: any error tied to this slug, or no matching binding,
  // aborts WITHOUT writing source or appending to the registry.
  const scan = scanFileForMarkers(relFile, nextContents, { config: options.commentConfig });
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
      registry_event_appended: false,
      scan_result: scanResult,
      errors: []
    };
  }

  // 7. Transactional commit: write source first (if edited), THEN append the
  // registry event (spec 8.1 transactional rule).
  if (!options.registerExisting) {
    // Preserve the source file's existing permission bits: rewriting a bound
    // shell script / hook must not drop its executable bit (100755 -> 100644).
    fs.writeText(absFile, nextContents, { preserveMode: true });
  }
  const event = bindingRegisteredEvent({
    command: "bind",
    rowId: options.rowId,
    bindingSlug,
    reason: options.registerExisting ? "register_existing" : "initial_bind",
    eventId: options.idFactory(),
    createdAt: options.clock(),
    version: options.version
  });
  appendJsonlLine(fs, options.bindingsPath, JSON.stringify(event));

  return {
    ...base,
    exit_code: 0,
    ok: true,
    registry_event_appended: true,
    scan_result: scanResult,
    next_command: `use-cases verify --row ${options.rowId}`,
    errors: []
  };
}
//: @use-case:end lifecycle.signals.bind_names_the_next_step
