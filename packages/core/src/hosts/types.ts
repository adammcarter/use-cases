import type { Diagnostic } from "../schema/index.js";

export type HostName = "claude" | "codex" | "copilot" | "opencode";
export type HostProjectionMode = "dry-run" | "write" | "revert";
export type HostSupportStatus =
  | "expected"
  | "installed"
  | "projected"
  | "conformant_static"
  | "verified_with_evidence"
  | "partial_with_evidence"
  | "blocked"
  | "unsupported"
  | "not_tested";

export type HostProfile = {
  schema_version: 1;
  profile_id: string;
  host: HostName;
  surface: string;
  profile_version: number;
  host_version: {
    min: string | null;
    tested: string | null;
    notes: string | null;
  };
  os_runtime: {
    supported: string[];
  };
  installation_mode: {
    expected: string;
  };
  permission_mode: {
    expected: string;
  };
  expected_capabilities: Record<string, "required" | "optional" | "unsupported">;
  projection_targets: HostProjectionTarget[];
  doctor_checks: string[];
  conformance_checks: string[];
  known_limitations: string[];
};

export type HostProjectionTarget = {
  kind: "activation_stub" | "skill_stub";
  path: string;
  managed: boolean;
  content_policy: "thin_stub" | "full_copy_required";
};

export type HostProfileLoadResult = {
  schema_version: 1;
  complete: boolean;
  profile: HostProfile | null;
  diagnostics: Diagnostic[];
};

export type ProjectionOperationAction =
  | "create"
  | "update_managed"
  | "skip_unchanged"
  | "conflict_user_modified"
  | "refuse_unsafe_path"
  | "delete_managed_on_revert";

export type HostProjectionOperation = {
  action: ProjectionOperationAction;
  path: string;
  reason: string;
  before_hash: string | null;
  after_hash: string | null;
};

export type HostProjectionResult = {
  schema_version: 1;
  host: HostName;
  surface: string;
  profile_id: string;
  mode: HostProjectionMode;
  complete: boolean;
  manifest_path: string;
  source_skill_hashes: Record<string, string>;
  operations: HostProjectionOperation[];
  diagnostics: Diagnostic[];
};

export type HostSupportSummary = {
  expected: boolean;
  installed: boolean;
  static_conformant: boolean;
  verified_with_evidence: boolean;
  evidence_event_ids: string[];
};

export type HostProductionSupportSummary = {
  profile_available: boolean;
  projected: boolean;
  static_conformant: boolean;
  executable_smoke: HostExecutableSmoke["status"];
  verified_with_evidence: boolean;
  evidence_event_ids: string[];
};

export type HostExecutableSmoke = {
  status: "passed" | "failed" | "not_run";
  executable: string;
  argv: string[];
  reason_code?:
    | "ok"
    | "executable_not_found"
    | "executable_unavailable"
    | "executable_timeout"
    | "executable_run_error"
    | "nonzero_exit";
  reason: string;
  exit_code: number | null;
  stdout?: string;
  stderr?: string;
};

export type HostDoctorResult = {
  schema_version: 1;
  host: HostName;
  surface: string;
  profile_id: string;
  support_status: HostSupportStatus;
  support: HostSupportSummary;
  checks: Array<{ id: string; result: "pass" | "fail" | "not_tested"; message: string }>;
  diagnostics: Diagnostic[];
};

export type HostConformanceResult = {
  schema_version: 1;
  host: HostName;
  surface: string;
  profile_id: string;
  checked_at: string;
  status_basis: "static_conformance_only";
  support_status: HostSupportStatus;
  support: HostProductionSupportSummary;
  profile_hash: string;
  projection_manifest_hash: string | null;
  evidence_event_ids: string[];
  executable_smoke: HostExecutableSmoke;
  checks: Array<{ id: string; result: "pass" | "fail" | "not_tested"; message: string }>;
  diagnostics: Diagnostic[];
};
