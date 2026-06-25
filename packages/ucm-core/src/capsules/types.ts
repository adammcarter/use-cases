import type { Diagnostic } from "../schema/index.js";
import type { PresentationPlanResult, PresentationMode } from "../presentation/types.js";

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
