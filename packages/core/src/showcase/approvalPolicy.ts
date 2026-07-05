import type { PresentationPlanItem } from "../presentation/index.js";
import { AssuranceTier, isAssuranceTier, tierMeetsFloor } from "./approvalTiers.js";

type ApprovalPolicySnapshot = PresentationPlanItem["approval_policy_snapshot"];
type PlanApprovalPolicySource = {
  selected_items?: Array<{
    approval_policy_snapshot: ApprovalPolicySnapshot;
  }>;
};

export function approvalAssuranceFloorForPlan(plan: PlanApprovalPolicySource | undefined): AssuranceTier {
  const floors = (plan?.selected_items ?? [])
    .map((item) => item.approval_policy_snapshot)
    .filter(policyRequiresUserApproval)
    .map(approvalAssuranceFloorForPolicy);

  if (floors.length === 0) {
    return AssuranceTier.TRUSTED_HOST_USER_PRESENCE;
  }

  return floors.reduce((floor, candidate) => (tierMeetsFloor(candidate, floor) ? candidate : floor));
}

function policyRequiresUserApproval(policy: ApprovalPolicySnapshot): boolean {
  return (
    policy.mode === "predefined" &&
    Array.isArray(policy.requirements) &&
    policy.requirements.some(
      (requirement) =>
        typeof requirement === "object" &&
        requirement !== null &&
        !Array.isArray(requirement) &&
        (requirement as { approver_type?: unknown }).approver_type === "user"
    )
  );
}

function approvalAssuranceFloorForPolicy(policy: ApprovalPolicySnapshot): AssuranceTier {
  return isAssuranceTier(policy.minimum_assurance_tier)
    ? policy.minimum_assurance_tier
    : AssuranceTier.TRUSTED_HOST_USER_PRESENCE;
}
