import { selectPlan } from "./selectPlan.js";
import { SHOWCASE_PROFILE } from "./scoring.js";
import type { PresentationPlanResult, PresentationPlanSelectionOptions } from "./types.js";

export function selectShowcasePlan(options: PresentationPlanSelectionOptions): PresentationPlanResult {
  return selectPlan(options, SHOWCASE_PROFILE);
}
