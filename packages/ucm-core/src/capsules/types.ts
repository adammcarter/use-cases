import type { Diagnostic } from "../schema/index.js";
import type { PresentationPlanResult, PresentationMode } from "../presentation/types.js";
import type { ResolvedWorkspaceContext } from "../roots.js";
import type { ShowcaseActorType, ShowcaseRunStatus } from "../showcase/types.js";
import type { HostSurface } from "../useCases/types.js";

export type DemoCapsuleCommandStep = {
  kind: "command";
  executable: string;
  argv: string[];
  working_directory: string;
  expected_exit_codes: number[];
};

export type DemoCapsuleRunbookStep =
  | { kind: "instruction"; text: string }
  | { kind: "observation"; text: string }
  | DemoCapsuleCommandStep;

export type DemoCapsuleItem = {
  use_case_id: string;
  scenario_ids?: string[];
  runbook: DemoCapsuleRunbookStep[];
};

export type DemoCapsule = {
  schema_version: 1;
  capsule_id: string;
  title: string;
  mode: PresentationMode;
  description: string;
  audience: string;
  timebox_seconds: number;
  items: DemoCapsuleItem[];
  permissions: {
    command_execution: boolean;
  };
  extensions?: Record<string, unknown>;
};

export type LoadedDemoCapsule = {
  capsule: DemoCapsule;
  path: string;
  semantic_hash: string;
};

export type CapsuleFileResult = {
  path: string;
  status: "loaded" | "parse_error" | "schema_error" | "io_error" | "symlink_rejected" | "path_escape";
  file_hash?: string;
};

export type CapsuleSnapshot = {
  schema_version: 1;
  complete: boolean;
  files: CapsuleFileResult[];
  capsules: LoadedDemoCapsule[];
  diagnostics: Diagnostic[];
};

export type CapsulePlanResult = {
  schema_version: 1;
  outcome: "generated" | "capsule_not_found" | "integrity_blocked";
  capsule: LoadedDemoCapsule | null;
  plan_result: PresentationPlanResult | null;
  diagnostics: Diagnostic[];
};

export type DemoCapsuleRunOptions = {
  context: ResolvedWorkspaceContext;
  capsuleId: string;
  executeCommands?: boolean;
  actorType?: Exclude<ShowcaseActorType, "user">;
  hostSurface?: HostSurface;
  idempotencyKey?: string;
  recordedAt?: string;
  commandTimeoutMs?: number;
};

export type DemoCapsulePendingStep = {
  item_index: number;
  step_index: number;
  use_case_id: string;
  reason: "command_execution_not_requested" | "runtime_observation_required";
};

export type DemoCapsuleCommandResult = {
  item_index: number;
  step_index: number;
  use_case_id: string;
  executable: string;
  argv: string[];
  working_directory: string;
  exit_code: number | null;
  signal: string | null;
  stdout: string;
  stderr: string;
  expected_exit_codes: number[];
  matched_expected_exit_code: boolean;
};

export type DemoCapsuleRunResult = {
  schema_version: 1;
  outcome: "performed" | "blocked";
  complete: boolean;
  capsule_id: string | null;
  run_id: string | null;
  events_written: string[];
  pending_steps: DemoCapsulePendingStep[];
  command_results: DemoCapsuleCommandResult[];
  status: ShowcaseRunStatus | null;
  plan_result: PresentationPlanResult | null;
  diagnostics: Diagnostic[];
};
