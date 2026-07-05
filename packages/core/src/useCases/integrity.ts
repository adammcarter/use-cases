import type { Diagnostic } from "../schema/index.js";
import type {
  AmbiguousIdGroup,
  LoadedUseCase,
  MatrixFileResult,
  MatrixListResultData,
  MatrixSnapshot,
  MatrixStructuralCounts,
  MatrixValidationResultData
} from "./types.js";

//: @use-case:matrix.product.integrity_degraded_nonfatal
export function buildMatrixSnapshot(input: {
  context: MatrixSnapshot["context"];
  files: MatrixFileResult[];
  candidates: LoadedUseCase[];
  diagnostics: Diagnostic[];
}): MatrixSnapshot {
  const diagnostics = [...input.context.diagnostics, ...input.diagnostics];
  const byId = groupByUseCaseId(input.candidates);
  const ambiguousUseCaseIds = Array.from(byId.entries())
    .filter(([, items]) => items.length > 1)
    .map(([id, items]): AmbiguousIdGroup => ({
      entity_kind: "use_case",
      id,
      source_paths: items.map((item) => item.source.path).sort()
    }))
    .sort((left, right) => left.id.localeCompare(right.id));
  const ambiguousIds = new Set(ambiguousUseCaseIds.map((item) => item.id));
  const addressableUseCases = input.candidates
    .filter((item) => !ambiguousIds.has(item.value.id))
    .sort((left, right) => left.value.id.localeCompare(right.value.id));

  for (const group of ambiguousUseCaseIds) {
    diagnostics.push({
      code: "duplicate_id",
      severity: "error",
      message: `Use case '${group.id}' appears in multiple files.`,
      source_path: group.source_paths[0] ?? null,
      json_pointer: null,
      entity_id: group.id,
      related_ids: group.source_paths
    });
  }

  const brokenSourceIds = new Set<string>();
  let brokenReferences = 0;
  for (const useCase of addressableUseCases) {
    for (const targetId of useCase.value.related_use_cases ?? []) {
      const target = byId.get(targetId);
      if (!target) {
        brokenReferences += 1;
        brokenSourceIds.add(useCase.value.id);
        diagnostics.push(referenceDiagnostic("broken_reference", useCase, targetId));
      } else if (target.length > 1) {
        brokenReferences += 1;
        brokenSourceIds.add(useCase.value.id);
        diagnostics.push(referenceDiagnostic("ambiguous_reference", useCase, targetId));
      }
    }
  }

  const blockingDiagnosticCount = diagnostics.filter((item) => item.severity === "error").length;
  const counts: MatrixStructuralCounts = {
    files_discovered: input.files.length,
    files_loaded: input.files.filter((file) => file.status === "loaded").length,
    files_excluded: input.files.filter((file) => file.status !== "loaded").length,
    use_case_candidates: input.candidates.length,
    use_cases_addressable: addressableUseCases.length,
    use_cases_ambiguous: input.candidates.filter((item) => ambiguousIds.has(item.value.id)).length,
    use_cases_structurally_clean: addressableUseCases.filter(
      (item) => !brokenSourceIds.has(item.value.id)
    ).length,
    broken_references: brokenReferences
  };
  const populated = input.candidates.length > 0;
  const state =
    blockingDiagnosticCount === 0
      ? "clean"
      : addressableUseCases.length > 0
        ? "partial"
        : "unusable";

  const snapshotBase = {
    context: input.context,
    complete: blockingDiagnosticCount === 0,
    integrity: {
      state,
      populated,
      blockingDiagnosticCount
    },
    files: input.files.sort((left, right) => left.path.localeCompare(right.path)),
    candidates: input.candidates,
    addressableUseCases,
    ambiguousUseCaseIds,
    diagnostics,
    counts,
    approvalTrust: input.context.approval_trust
  } satisfies Omit<MatrixSnapshot, "resolveUseCase" | "resolveScenario">;

  return {
    ...snapshotBase,
    resolveUseCase(id) {
      const candidates = byId.get(id);
      if (!candidates) {
        return { kind: "missing", id };
      }
      if (candidates.length > 1) {
        return { kind: "ambiguous", id, candidates };
      }
      return { kind: "resolved", id, useCase: candidates[0] };
    },
    resolveScenario(useCaseId, scenarioId) {
      const resolved = this.resolveUseCase(useCaseId);
      if (resolved.kind !== "resolved") {
        return resolved.kind === "ambiguous"
          ? { kind: "ambiguous", useCaseId, scenarioId, candidates: resolved.candidates }
          : { kind: "missing", useCaseId, scenarioId };
      }
      const scenarios = resolved.useCase.value.scenarios ?? [];
      const matches = scenarios.filter((scenario) => scenario.id === scenarioId);
      if (matches.length === 0) {
        return { kind: "missing", useCaseId, scenarioId };
      }
      if (matches.length > 1) {
        return { kind: "ambiguous", useCaseId, scenarioId, candidates: [resolved.useCase] };
      }
      return { kind: "resolved", useCaseId, scenarioId, useCase: resolved.useCase };
    }
  };
}

//: @use-case:end matrix.product.integrity_degraded_nonfatal
export function toMatrixValidationResult(snapshot: MatrixSnapshot): MatrixValidationResultData {
  return {
    schema_version: 1,
    complete: snapshot.complete,
    valid: snapshot.complete,
    integrity: {
      state: snapshot.integrity.state,
      populated: snapshot.integrity.populated,
      blocking_diagnostic_count: snapshot.integrity.blockingDiagnosticCount
    },
    files: snapshot.files.map((file) => ({
      path: file.path,
      status: file.status,
      ...(file.semantic_hash ? { semantic_hash: file.semantic_hash } : {}),
      ...(file.file_hash ? { file_hash: file.file_hash } : {})
    })),
    counts: snapshot.counts,
    ambiguous_ids: snapshot.ambiguousUseCaseIds
  };
}

export function toMatrixListResult(
  snapshot: MatrixSnapshot,
  useCases: LoadedUseCase[]
): MatrixListResultData {
  return {
    schema_version: 1,
    complete: snapshot.complete,
    integrity: {
      state: snapshot.integrity.state,
      populated: snapshot.integrity.populated,
      blocking_diagnostic_count: snapshot.integrity.blockingDiagnosticCount
    },
    use_cases: useCases.map((item) => ({
      id: item.value.id,
      title: item.value.title,
      feature_id: item.feature.id,
      lifecycle: item.value.lifecycle,
      value_tier: item.value.value_tier,
      journey_role: item.value.journey_role,
      source_path: item.source.path,
      semantic_hash: item.semanticHash,
      host_surfaces: (item.value.host_applicability ?? [])
        .filter((host) => host.supported)
        .map((host) => host.host_surface),
      tags: item.value.tags ?? []
    })),
    counts: {
      returned: useCases.length,
      total_addressable: snapshot.addressableUseCases.length
    }
  };
}

function groupByUseCaseId(candidates: LoadedUseCase[]): Map<string, LoadedUseCase[]> {
  const byId = new Map<string, LoadedUseCase[]>();
  for (const candidate of candidates) {
    const current = byId.get(candidate.value.id) ?? [];
    current.push(candidate);
    byId.set(candidate.value.id, current);
  }
  return byId;
}

function referenceDiagnostic(code: "broken_reference" | "ambiguous_reference", useCase: LoadedUseCase, targetId: string): Diagnostic {
  return {
    code,
    severity: "error",
    message: `Use case '${useCase.value.id}' references ${code === "broken_reference" ? "missing" : "ambiguous"} use case '${targetId}'.`,
    source_path: useCase.source.path,
    json_pointer: `${useCase.source.jsonPointer}/related_use_cases`,
    entity_id: useCase.value.id,
    related_ids: [targetId]
  };
}
