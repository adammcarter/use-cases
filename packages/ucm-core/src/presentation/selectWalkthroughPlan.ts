import { selectPlan } from "./selectPlan.js";
import { WALKTHROUGH_PROFILE } from "./scoring.js";
import type { PresentationPlanResult, PresentationPlanSelectionOptions } from "./types.js";

export function selectWalkthroughPlan(options: PresentationPlanSelectionOptions): PresentationPlanResult {
  return selectPlan(options, WALKTHROUGH_PROFILE);
}
