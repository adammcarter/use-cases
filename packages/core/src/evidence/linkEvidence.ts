import type { MatrixSnapshot } from "../useCases/types.js";
import type { EvidenceMatrixLink, EvidenceSnapshot } from "./types.js";

//: @use-case: evidence.ledger.product_proof_map
export function linkEvidenceToMatrix(
  evidence: EvidenceSnapshot,
  matrix: MatrixSnapshot
): EvidenceMatrixLink[] {
  const links: EvidenceMatrixLink[] = [];
  for (const aggregate of evidence.aggregates) {
    for (const target of aggregate.targetLinks) {
      const resolved = matrix.resolveUseCase(target.use_case_id);
      if (!matrix.complete && resolved.kind === "missing") {
        links.push({
          evidenceId: aggregate.evidenceId,
          useCaseId: target.use_case_id,
          scenarioId: target.scenario_id,
          resolution: "unknown_due_to_matrix_incomplete",
          semanticHash: "unknown",
          sourcePath: null
        });
        continue;
      }
      if (resolved.kind === "missing") {
        links.push({
          evidenceId: aggregate.evidenceId,
          useCaseId: target.use_case_id,
          scenarioId: target.scenario_id,
          resolution: "missing",
          semanticHash: "unknown",
          sourcePath: null
        });
        continue;
      }
      if (resolved.kind === "ambiguous") {
        links.push({
          evidenceId: aggregate.evidenceId,
          useCaseId: target.use_case_id,
          scenarioId: target.scenario_id,
          resolution: "ambiguous",
          semanticHash: "unknown",
          sourcePath: null
        });
        continue;
      }
      links.push({
        evidenceId: aggregate.evidenceId,
        useCaseId: target.use_case_id,
        scenarioId: target.scenario_id,
        resolution: "resolved",
        semanticHash:
          resolved.useCase.semanticHash === target.use_case_semantic_hash ? "match" : "mismatch",
        sourcePath: resolved.useCase.source.path
      });
    }
  }
  return links.sort((left, right) =>
    `${left.evidenceId}:${left.useCaseId}`.localeCompare(`${right.evidenceId}:${right.useCaseId}`)
  );
}
//: @use-case: end evidence.ledger.product_proof_map
