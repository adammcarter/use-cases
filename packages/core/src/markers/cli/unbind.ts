// `unbind` command core: end a binding.
//
// Removes the marker from the source (wherever it is) and appends ONE
// `binding_released` event, so the slug is free to be bound again and the row it
// named is free to leave the matrix. This is the exit path `bind` never had —
// before it, removing the markers by hand did NOT release the registration, so a
// binding on the wrong declaration was permanent through the tool.
//
// Deliberately weaker preconditions than bind, because the states worth escaping
// are exactly the broken ones:
//   * the row need not exist in the matrix (that is the retire / rename case);
//   * the marker need not exist in the source (already stripped by hand);
//   * the marker's span need not resolve (a marker on a non-func, say).
// It stays strict about the one thing that matters: the slug must currently be
// registered, and every OTHER registry error still fails closed.
import type { ResolvedWorkspaceContext } from "../../roots.js";
import type { CommentPrefixConfig } from "../commentPrefix.js";
import { isValidSlug } from "../markerLine.js";
import { RegistryErrorCode, validateBindingsJsonl } from "../registry.js";
import {
  bindingReleasedEvent,
  findSlugMarker,
  removeMarkerLines,
  type MarkerLocation
} from "./bindingLifecycle.js";
import { appendJsonlLine, nodeMarkerFs, type MarkerFs } from "./io.js";
import { loadMarkerRows, resolveUnderRoot } from "./shared.js";

export interface UnbindCommandOptions {
  context: ResolvedWorkspaceContext;
  productRoot: string;
  bindingsPath: string;
  rowId: string;
  suffix?: string;
  // Recorded on the release event: why the binding ended.
  reason?: string;
  dryRun?: boolean;
  clock: () => string;
  idFactory: () => string;
  version?: string;
  fs?: MarkerFs;
  commentConfig?: CommentPrefixConfig;
}

export interface UnbindCommandError {
  code: string;
  message: string;
}

export interface UnbindCommandResult {
  exit_code: number;
  ok: boolean;
  command: "unbind";
  row_id: string;
  binding_slug: string;
  registry_event_appended: boolean;
  // Empty when the marker was already gone from the source.
  markers_removed: MarkerLocation[];
  next_command?: string;
  errors: UnbindCommandError[];
}

function fail(
  rowId: string,
  bindingSlug: string,
  exitCode: number,
  error: UnbindCommandError
): UnbindCommandResult {
  return {
    exit_code: exitCode,
    ok: false,
    command: "unbind",
    row_id: rowId,
    binding_slug: bindingSlug,
    registry_event_appended: false,
    markers_removed: [],
    errors: [error]
  };
}

// The registry errors `unbind` is allowed to run despite, because releasing this
// slug is what CLEARS them. Anything else (a parse error, a schema violation, a
// conflict on another slug) still fails closed at exit 4.
function blockingRegistryErrors(
  errors: ReadonlyArray<{ code: string; binding_slug?: string; message: string }>,
  bindingSlug: string
): ReadonlyArray<{ code: string; message: string }> {
  return errors.filter((error) => {
    const selfInflicted =
      error.binding_slug === bindingSlug &&
      (error.code === RegistryErrorCode.REGISTRY_ROW_MISSING ||
        error.code === RegistryErrorCode.SLUG_PREFIX_MISMATCH);
    return !selfInflicted;
  });
}

export function runUnbindCommand(options: UnbindCommandOptions): UnbindCommandResult {
  const fs = options.fs ?? nodeMarkerFs;
  const bindingSlug = options.suffix ? `${options.rowId}#${options.suffix}` : options.rowId;

  if (!isValidSlug(bindingSlug)) {
    return fail(options.rowId, bindingSlug, 3, {
      code: "MALFORMED_MARKER",
      message: `binding slug ${bindingSlug} is not a valid use-case slug`
    });
  }

  // The row is loaded for its ids only — a row that has LEFT the matrix is a
  // reason to unbind, never a reason to refuse.
  const loaded = loadMarkerRows(options.context);
  const bindingsText = fs.readText(options.bindingsPath) ?? "";
  const validation = validateBindingsJsonl(bindingsText, loaded.rowIds);
  const blocking = blockingRegistryErrors(validation.errors, bindingSlug);
  if (blocking.length > 0) {
    return fail(options.rowId, bindingSlug, 4, {
      code: "REGISTRY_INVALID",
      message: `binding registry is not valid: ${blocking.map((error) => error.message).join("; ")}`
    });
  }

  if (!validation.registry.slugToRow.has(bindingSlug)) {
    return fail(options.rowId, bindingSlug, 2, {
      code: "NOT_REGISTERED",
      message: `binding slug ${bindingSlug} is not registered, so there is nothing to release`
    });
  }

  // Find the marker wherever it sits in the product tree (it may have been moved
  // to another file, or removed entirely).
  const found = findSlugMarker({
    fs,
    productRoot: options.productRoot,
    slug: bindingSlug,
    commentConfig: options.commentConfig,
    skipPaths: [options.context.data_root]
  });

  const markersRemoved = found ? [found.location] : [];

  if (options.dryRun) {
    return {
      exit_code: 0,
      ok: true,
      command: "unbind",
      row_id: options.rowId,
      binding_slug: bindingSlug,
      registry_event_appended: false,
      markers_removed: markersRemoved,
      errors: []
    };
  }

  // Source first, then the registry event — the same transactional order bind
  // uses, so a crash between the two leaves an UNREGISTERED marker (loud) rather
  // than a registration pointing at nothing (silent).
  if (found) {
    fs.writeText(
      resolveUnderRoot(options.productRoot, found.location.file_path),
      removeMarkerLines(found.contents, found.location),
      { preserveMode: true }
    );
  }
  appendJsonlLine(
    fs,
    options.bindingsPath,
    JSON.stringify(
      bindingReleasedEvent({
        command: "unbind",
        rowId: options.rowId,
        bindingSlug,
        reason: options.reason ?? "unbind",
        eventId: options.idFactory(),
        createdAt: options.clock(),
        version: options.version
      })
    )
  );

  return {
    exit_code: 0,
    ok: true,
    command: "unbind",
    row_id: options.rowId,
    binding_slug: bindingSlug,
    registry_event_appended: true,
    markers_removed: markersRemoved,
    // A released row proves nothing until it is bound again, so say so.
    next_command: loaded.rowIds.has(options.rowId)
      ? `use-cases bind --row ${options.rowId} --file <file> --mode <mode>`
      : "use-cases scan",
    errors: []
  };
}
