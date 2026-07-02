import { DEFAULT_COMPONENT_ID } from "../version.js";
import type { Diagnostic } from "./diagnostic.js";

export type CliContext = {
  workspace_root: string;
  data_root: string;
  component_id: string;
  workspace_snapshot: {
    repository_id: string;
    vcs: "git" | "none" | "unknown";
    head_revision: string;
    dirty: boolean;
    working_tree_digest: string;
    component_id: string;
    captured_at: string;
  };
};

export type CliResult<T> = {
  schema_version: 1;
  protocol_version: 1;
  command: string;
  ok: boolean;
  complete: boolean;
  data: T;
  diagnostics: Diagnostic[];
  context: CliContext;
};

export function createCliResult<T>(
  command: string,
  data: T,
  options: {
    ok?: boolean;
    complete?: boolean;
    diagnostics?: Diagnostic[];
    workspaceRoot?: string;
    dataRoot?: string;
    componentId?: string;
  } = {}
): CliResult<T> {
  const workspaceRoot = options.workspaceRoot ?? process.cwd();
  const dataRoot = options.dataRoot ?? workspaceRoot;
  const componentId = options.componentId ?? DEFAULT_COMPONENT_ID;
  const diagnostics = options.diagnostics ?? [];
  // An error-severity diagnostic always means the command did not succeed, so
  // the envelope's ok must be false regardless of the caller-provided value.
  const hasError = diagnostics.some((item) => item.severity === "error");
  const ok = hasError ? false : (options.ok ?? true);
  return {
    schema_version: 1,
    protocol_version: 1,
    command,
    ok,
    complete: options.complete ?? true,
    data,
    diagnostics,
    context: {
      workspace_root: workspaceRoot,
      data_root: dataRoot,
      component_id: componentId,
      workspace_snapshot: {
        repository_id: "unknown",
        vcs: "unknown",
        head_revision: "unknown",
        dirty: false,
        working_tree_digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000",
        component_id: componentId,
        captured_at: new Date(0).toISOString()
      }
    }
  };
}
