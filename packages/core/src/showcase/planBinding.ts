import { readFileSync } from "node:fs";
import { computePresentationPlanHash, type PresentationPlan } from "../presentation/index.js";
import { UseCasesPluginError } from "../errors.js";

export const PLACEHOLDER_HASH = "sha256:0000000000000000000000000000000000000000000000000000000000000000";

export function loadPresentationPlanFile(path: string): PresentationPlan {
  let parsed: unknown;
  try {
    parsed = JSON.parse(readFileSync(path, "utf8")) as unknown;
  } catch (error) {
    throw new UseCasesPluginError(
      `Presentation plan file could not be read: ${error instanceof Error ? error.message : String(error)}`,
      "showcase_plan_file_unreadable"
    );
  }
  assertPresentationPlanShape(parsed);
  assertPresentationPlanHash(parsed);
  return parsed;
}

export function assertPresentationPlanHash(plan: PresentationPlan): void {
  if (plan.plan_content_hash === PLACEHOLDER_HASH) {
    throw new UseCasesPluginError("Plan content hash must not be a placeholder.", "showcase_plan_placeholder_hash");
  }
  if (computePresentationPlanHash(plan) !== plan.plan_content_hash) {
    throw new UseCasesPluginError("Plan content hash does not match plan body.", "showcase_plan_hash_mismatch");
  }
}

function assertPresentationPlanShape(value: unknown): asserts value is PresentationPlan {
  if (!isRecord(value) || value.schema_version !== 1 || typeof value.plan_content_hash !== "string") {
    throw new UseCasesPluginError("Presentation plan file is not a v1 plan.", "showcase_plan_file_invalid");
  }
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
