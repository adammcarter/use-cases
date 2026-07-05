import type { Diagnostic } from "../schema/index.js";
import type { ResolvedWorkspaceContext } from "../roots.js";

export type MatrixIntegrityState = "clean" | "partial" | "unusable";
export type MatrixFileStatus =
  | "loaded"
  | "parse_error"
  | "schema_error"
  | "unknown_version"
  | "duplicate_id"
  | "broken_reference"
  | "ambiguous_reference"
  | "path_escape"
  | "symlink_rejected"
  | "io_error"
  | "resource_limit_exceeded";

export type HostSurface =
  | "claude.cli"
  | "claude.desktop"
  | "codex.cli"
  | "copilot.cli"
  | "copilot.github"
  | "opencode.cli"
  | "unknown";

export type ApprovalPolicyMinimumAssuranceTier =
  | "untrusted_automation"
  | "same_channel_operator_confirmation"
  | "trusted_host_user_presence"
  | "webauthn_hardware";

export type ApprovalPolicyV1 =
  | {
      mode: "none";
      required_for_release?: boolean;
      minimum_assurance_tier?: ApprovalPolicyMinimumAssuranceTier;
    }
  | {
      mode: "ask";
      required_for_release?: boolean;
      minimum_assurance_tier?: ApprovalPolicyMinimumAssuranceTier;
    }
  | {
      mode: "predefined";
      required_for_release?: boolean;
      minimum_assurance_tier?: ApprovalPolicyMinimumAssuranceTier;
      requirements: Array<{
        approver_type: "user" | "agent";
        minimum_count: number;
      }>;
      statement: string;
    };

export type UseCaseV1 = {
  id: string;
  title: string;
  lifecycle: "planned" | "active" | "deprecated" | "removed";
  value_tier: "critical" | "core" | "supporting" | "long_tail";
  journey_role: "golden" | "alternate" | "edge" | "negative" | "failure";
  usage_frequency: "common" | "occasional" | "rare";
  tags?: string[];
  source_refs?: Array<{ kind: "file"; path: string }>;
  related_use_cases?: string[];
  scenarios?: Array<{ id: string; kind: string }>;
  host_applicability?: Array<{
    host_surface: HostSurface;
    supported: boolean;
    notes?: string;
  }>;
  approval_policy?: ApprovalPolicyV1;
  [key: string]: unknown;
};

export type FeatureV1 = {
  id: string;
  name: string;
  summary: string;
};

export type LoadedUseCase = {
  value: UseCaseV1;
  feature: FeatureV1;
  semanticHash: string;
  source: {
    path: string;
    jsonPointer: string;
    fileByteHash: string;
  };
};

export type MatrixFileResult = {
  path: string;
  status: MatrixFileStatus;
  semantic_hash?: string;
  file_hash?: string;
};

export type AmbiguousIdGroup = {
  entity_kind: "use_case";
  id: string;
  source_paths: string[];
};

export type MatrixStructuralCounts = {
  files_discovered: number;
  files_loaded: number;
  files_excluded: number;
  use_case_candidates: number;
  use_cases_addressable: number;
  use_cases_ambiguous: number;
  use_cases_structurally_clean: number;
  broken_references: number;
};

export type UseCaseResolution =
  | { kind: "resolved"; id: string; useCase: LoadedUseCase }
  | { kind: "missing"; id: string }
  | { kind: "ambiguous"; id: string; candidates: LoadedUseCase[] };

export type ScenarioResolution =
  | { kind: "resolved"; useCaseId: string; scenarioId: string; useCase: LoadedUseCase }
  | { kind: "missing"; useCaseId: string; scenarioId: string }
  | { kind: "ambiguous"; useCaseId: string; scenarioId: string; candidates: LoadedUseCase[] };

export type MatrixSnapshot = {
  context: ResolvedWorkspaceContext;
  complete: boolean;
  integrity: {
    state: MatrixIntegrityState;
    populated: boolean;
    blockingDiagnosticCount: number;
  };
  files: MatrixFileResult[];
  candidates: LoadedUseCase[];
  addressableUseCases: LoadedUseCase[];
  ambiguousUseCaseIds: AmbiguousIdGroup[];
  diagnostics: Diagnostic[];
  counts: MatrixStructuralCounts;
  approvalTrust?: ResolvedWorkspaceContext["approval_trust"];
  resolveUseCase(id: string): UseCaseResolution;
  resolveScenario(useCaseId: string, scenarioId: string): ScenarioResolution;
};

export type MatrixValidationResultData = {
  schema_version: 1;
  complete: boolean;
  valid: boolean;
  integrity: {
    state: MatrixIntegrityState;
    populated: boolean;
    blocking_diagnostic_count: number;
  };
  files: Array<{
    path: string;
    status: MatrixFileStatus;
    semantic_hash?: string;
    file_hash?: string;
  }>;
  counts: MatrixStructuralCounts;
  ambiguous_ids: AmbiguousIdGroup[];
};

export type MatrixListResultData = {
  schema_version: 1;
  complete: boolean;
  integrity: MatrixValidationResultData["integrity"];
  use_cases: Array<{
    id: string;
    title: string;
    feature_id: string;
    lifecycle: UseCaseV1["lifecycle"];
    value_tier: UseCaseV1["value_tier"];
    journey_role: UseCaseV1["journey_role"];
    source_path: string;
    semantic_hash: string;
    host_surfaces: HostSurface[];
    tags: string[];
  }>;
  counts: {
    returned: number;
    total_addressable: number;
  };
};
