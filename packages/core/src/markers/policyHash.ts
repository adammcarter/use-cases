import { canonicalJsonSha256 } from "./canonicalJson.js";

// Hash of an arbitrary policy object via canonical_json + sha256.
export function computePolicyHash(policy: unknown): string {
  return canonicalJsonSha256(policy);
}

// verification_policy_hash: hash of the row's verification_policy object.
export function computeVerificationPolicyHash(verificationPolicy: unknown): string {
  return computePolicyHash(verificationPolicy);
}

// approval_policy_hash: hash of the row's approval_policy object.
export function computeApprovalPolicyHash(approvalPolicy: unknown): string {
  return computePolicyHash(approvalPolicy);
}
