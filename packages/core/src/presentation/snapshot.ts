import { existsSync, readFileSync } from "node:fs";
import { join } from "node:path";
import { computeSemanticHash } from "../schema/index.js";
import type { EvidenceSnapshot } from "../evidence/types.js";
import type { PresentationPlan, PresentationPlanSelectionOptions } from "./types.js";

/**
 * Input / workspace snapshot construction: the deterministic digests and
 * workflow snapshot that pin a plan to the inputs it was generated from, plus
 * the plan id derivation.
 */

export function matrixDigest(options: PresentationPlanSelectionOptions): string {
  return computeSemanticHash({
    complete: options.matrix.complete,
    integrity: options.matrix.integrity,
    use_cases: options.matrix.addressableUseCases.map((item) => ({
      id: item.value.id,
      semantic_hash: item.semanticHash,
      source_path: item.source.path
    }))
  });
}

export function evidenceDigest(evidence: EvidenceSnapshot, useCaseIds: string[]): string {
  const ids = new Set(useCaseIds);
  const aggregates = evidence.aggregates
    .filter((aggregate) => aggregate.targetLinks.some((target) => ids.has(target.use_case_id)))
    .map((aggregate) => ({
      evidence_id: aggregate.evidenceId,
      status: aggregate.status,
      event_ids: aggregate.eventIds,
      target_links: aggregate.targetLinks,
      freshness_inputs: aggregate.freshnessInputs
    }));
  return computeSemanticHash({
    complete: evidence.complete,
    integrity: evidence.integrity,
    aggregates
  });
}

export function workflowSnapshot(options: PresentationPlanSelectionOptions): PresentationPlan["input_snapshot"]["workflow"] {
  const configPath = join(options.context.workspace_root, "use-cases-plugin.yml");
  if (!existsSync(configPath)) {
    return { effective_mode: "continuous", source: "default", advisory: true };
  }
  const source = readFileSync(configPath, "utf8");
  const effectiveMode = source.match(/^default_workflow_mode:\s*([a-z_]+)/m)?.[1] ?? "continuous";
  return {
    effective_mode: effectiveMode,
    source: source.match(/^default_workflow_mode:/m) ? "workspace_config" : "default",
    advisory: true
  };
}

export function planId(mode: "showcase" | "walkthrough", generatedAt: string): string {
  return `plan.${mode}.${generatedAt.toLowerCase().replace(/[^a-z0-9]+/g, "_").replace(/^_+|_+$/g, "")}`;
}
