// F3 — trust is COMPUTED from a signed, run-bound approval token; it is NEVER
// handed in as a caller-asserted boolean or inferred from a capture_method
// string. This module is the single place that decides "does this user
// approval/rejection event count as a genuine human sign-off?" and it answers
// ONLY by re-verifying the embedded ed25519 approval_token against a keyring
// resolver + the run binding.
//
// The pre-F3 caller-asserted booleans (stdinIsTty / confirmed / verified) and
// the capture_method-string trust path are DELETED. They were the live hole:
// `uc showcase approve --actor user` stamped capture_method
// =trusted_user_interactive_cli and the replay verifier trusted that string
// with no signature.
import type { PublicKeyResolver } from "../markers/proofSignature.js";
import type { AssuranceTierResolver } from "../markers/keyring.js";
import { AssuranceTier } from "./approvalTiers.js";
import {
  verifyApprovalToken,
  type ApprovalRequestBinding,
  type ApprovalDecision,
  type ApprovalToken
} from "./approvalToken.js";
import type { ShowcaseActorType, ShowcaseEvent } from "./types.js";

// What replay needs to recompute trust: the resolver(s) and (optionally) the
// run's live binding. Absent a resolver, EVERY user approval is untrusted
// (fail-closed), so tokenless legacy approvals degrade to pending under a
// non-spoofable policy.
export interface ApprovalTrustContext {
  resolver?: PublicKeyResolver;
  tierResolver?: AssuranceTierResolver;
  assuranceFloor?: AssuranceTier;
  // The live run binding to re-check the embedded token against. When omitted,
  // the token's own embedded binding is used (append-time already enforced the
  // cross-run equality against the live run).
  liveBinding?: ApprovalRequestBinding;
  nowMs?: number;
}

// Pull the embedded signed approval token from a user approval/rejection event.
export function embeddedApprovalToken(event: ShowcaseEvent): ApprovalToken | undefined {
  const token = (event.payload as { approval_token?: unknown }).approval_token;
  if (
    token &&
    typeof token === "object" &&
    (token as { approval_token_schema?: unknown }).approval_token_schema === "ucase-approval-token-v1"
  ) {
    return token as ApprovalToken;
  }
  return undefined;
}

export type TrustedUserDecisionMetadata = {
  actor_type: ShowcaseActorType;
  assurance_tier: AssuranceTier;
  decision: ApprovalDecision;
  key_id: string;
};

// Return the verified facts for a trusted user approval/rejection event. The
// assurance tier comes from verifyApprovalToken's keyring-backed verification,
// not from a caller-supplied display string.
export function trustedUserDecisionMetadata(
  event: ShowcaseEvent,
  trust: ApprovalTrustContext = {}
): TrustedUserDecisionMetadata | null {
  if (event.actor_type !== "user") {
    return null;
  }
  if (event.event_type !== "approval_recorded" && event.event_type !== "approval_rejected") {
    return null;
  }
  const token = embeddedApprovalToken(event);
  if (!token || !trust.resolver) {
    return null;
  }
  const floor = trust.tierResolver
    ? trust.assuranceFloor ?? AssuranceTier.TRUSTED_HOST_USER_PRESENCE
    : AssuranceTier.UNTRUSTED_AUTOMATION;
  const result = verifyApprovalToken({
    token,
    resolver: trust.resolver,
    tierResolver: trust.tierResolver,
    liveBinding: trust.liveBinding ?? token.binding,
    isNonceBurned: () => false,
    nowMs: trust.nowMs ?? Date.parse(token.iat),
    assuranceFloor: floor
  });
  if (!result.ok) {
    return null;
  }
  return {
    actor_type: event.actor_type,
    assurance_tier: result.assurance_tier,
    decision: result.decision,
    key_id: result.key_id
  };
}

// The replay-side trust decision. A user decision event is trusted ONLY when it
// carries a structurally-valid signed approval_token that verifies against the
// resolver at or above the assurance floor. No token, no resolver, a
// capture_method string alone, or a bad signature => NOT trusted.
export function isTrustedUserDecisionEvent(event: ShowcaseEvent, trust: ApprovalTrustContext = {}): boolean {
  if (event.actor_type !== "user") {
    return true; // non-user actors are governed elsewhere (they cannot user-sign)
  }
  if (event.event_type !== "approval_recorded" && event.event_type !== "approval_rejected") {
    return true;
  }
  return trustedUserDecisionMetadata(event, trust) !== null;
}
