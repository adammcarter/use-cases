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
  type ApprovalToken
} from "./approvalToken.js";
import type { ShowcaseEvent } from "./types.js";

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
  const token = embeddedApprovalToken(event);
  if (!token || !trust.resolver) {
    return false; // fail-closed: no signed token / no way to verify => untrusted
  }
  // The assurance-tier floor was already enforced at APPEND time (a token below
  // the floor was never embedded in an accepted approval). At replay we may not
  // have the keyring's tier map, so we only re-enforce the floor when a tier
  // resolver is actually supplied; otherwise a valid signature + binding is the
  // replay gate.
  const floor = trust.tierResolver
    ? trust.assuranceFloor ?? AssuranceTier.TRUSTED_HOST_USER_PRESENCE
    : AssuranceTier.UNTRUSTED_AUTOMATION;
  const result = verifyApprovalToken({
    token,
    resolver: trust.resolver,
    tierResolver: trust.tierResolver,
    liveBinding: trust.liveBinding ?? token.binding,
    // Replay: the token is expected to be already-burned in the ledger by
    // design, so the single-use gate is not re-run here (append-time owns it).
    isNonceBurned: () => false,
    // Replay must not reject a legitimately-approved run just because the token's
    // exp has since passed; expiry is an append-time gate. Use the token's own
    // iat so the keyring validity window still holds.
    nowMs: trust.nowMs ?? Date.parse(token.iat),
    assuranceFloor: floor
  });
  return result.ok;
}
