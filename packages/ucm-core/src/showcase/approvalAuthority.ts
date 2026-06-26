import { PresentationSkillsError } from "../errors.js";
import type { ShowcaseActorType, ShowcaseEvent } from "./types.js";

export type TrustedApprovalAuthority =
  | { kind: "trusted_interactive_cli"; stdinIsTty: boolean; confirmed: boolean }
  | { kind: "trusted_host_token"; token: string; verified: boolean }
  | { kind: "untrusted_automation" };

export function requireTrustedUserApprovalAuthority(input: {
  actorType: ShowcaseActorType;
  authority?: TrustedApprovalAuthority;
  userApprovalRequired: boolean;
}): void {
  if (input.actorType !== "user") {
    if (input.userApprovalRequired) {
      throw new PresentationSkillsError("Agent cannot record user-required approval.", "showcase.user_required_approval");
    }
    return;
  }

  if (!isTrustedAuthority(input.authority)) {
    throw new PresentationSkillsError(
      "User approval requires a trusted interactive user confirmation path.",
      "showcase.trusted_user_confirmation_required"
    );
  }
}

export function isTrustedUserDecisionEvent(event: ShowcaseEvent): boolean {
  if (event.actor_type !== "user") {
    return true;
  }
  return event.payload.capture_method === "trusted_user_interactive_cli";
}

function isTrustedAuthority(authority: TrustedApprovalAuthority | undefined): boolean {
  if (!authority) {
    return false;
  }
  if (authority.kind === "trusted_interactive_cli") {
    return authority.stdinIsTty && authority.confirmed;
  }
  if (authority.kind === "trusted_host_token") {
    return authority.verified;
  }
  return false;
}
