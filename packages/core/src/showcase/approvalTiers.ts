// F3 — assurance tiers for human approval.
//
// A tier answers ONE question: does an approval carrying this tier count as a
// real human's out-of-band sign-off? The keyring binds only the MAXIMUM tier a
// key may assert. A signed token records the method that was actually used and
// the tier claimed from that method.
//
// Policy picks a FLOOR; an approval satisfies the policy only when its key's
// tier is at or above that floor on the ordered ladder below.

export const AssuranceTier = Object.freeze({
  // An automated / in-session signer. Excluded from every human-sign-off policy.
  UNTRUSTED_AUTOMATION: "untrusted_automation",
  // The old "hardened TTY". Still agent-spoofable (an agent can drive its own
  // PTY), so it is explicitly NOT trusted for human sign-off. Weak fallback only.
  SAME_CHANNEL_OPERATOR_CONFIRMATION: "same_channel_operator_confirmation",
  // A token signed by a key held in host/OS custody outside the agent's scope,
  // keyring-verified. THE v1 target tier for "a human really approved this".
  TRUSTED_HOST_USER_PRESENCE: "trusted_host_user_presence"
  // (deferred slot: webauthn_hardware — a hardware-attested tier above this.)
} as const);

export type AssuranceTier = (typeof AssuranceTier)[keyof typeof AssuranceTier];

export const AssuranceMethod = Object.freeze({
  AUTOMATION: "automation",
  SAME_CHANNEL: "same_channel",
  OS_PRESENCE: "os_presence"
} as const);

export type AssuranceMethod = (typeof AssuranceMethod)[keyof typeof AssuranceMethod];

export const ASSURANCE_METHOD_TO_TIER: Record<AssuranceMethod, AssuranceTier> = Object.freeze({
  [AssuranceMethod.AUTOMATION]: AssuranceTier.UNTRUSTED_AUTOMATION,
  [AssuranceMethod.SAME_CHANNEL]: AssuranceTier.SAME_CHANNEL_OPERATOR_CONFIRMATION,
  [AssuranceMethod.OS_PRESENCE]: AssuranceTier.TRUSTED_HOST_USER_PRESENCE
});

// Ordered weakest -> strongest. Index is the ladder rank; a higher (deferred)
// hardware tier would append here.
const LADDER: AssuranceTier[] = [
  AssuranceTier.UNTRUSTED_AUTOMATION,
  AssuranceTier.SAME_CHANNEL_OPERATOR_CONFIRMATION,
  AssuranceTier.TRUSTED_HOST_USER_PRESENCE
];

// Fail-closed: anything unrecognised (including undefined / a bogus string) is
// treated as the weakest tier.
export function normalizeAssuranceTier(value: unknown): AssuranceTier {
  return LADDER.find((tier) => tier === value) ?? AssuranceTier.UNTRUSTED_AUTOMATION;
}

export function isAssuranceTier(value: unknown): value is AssuranceTier {
  return LADDER.some((tier) => tier === value);
}

export function isAssuranceMethod(value: unknown): value is AssuranceMethod {
  return Object.values(AssuranceMethod).some((method) => method === value);
}

export function assuranceTierForMethod(method: AssuranceMethod): AssuranceTier {
  return ASSURANCE_METHOD_TO_TIER[method];
}

// Is `tier` at or above `floor` on the ladder?
export function tierMeetsFloor(tier: AssuranceTier, floor: AssuranceTier): boolean {
  return LADDER.indexOf(tier) >= LADDER.indexOf(floor);
}

// Does a tier count as a genuine human sign-off (v1 target and above)?
export function trustedForHumanSignoff(tier: AssuranceTier): boolean {
  return tierMeetsFloor(tier, AssuranceTier.TRUSTED_HOST_USER_PRESENCE);
}
