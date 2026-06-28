import type { DeliveryKind } from "./types.js";

/**
 * The six presentation formats. The agent picks exactly one per item up front
 * and surfaces it to the user with a fixed, scannable header + body.
 */
export type PresentationFormat =
  | "testing"
  | "comparing"
  | "inspecting"
  | "reviewing"
  | "user_led"
  | "explaining";

export type FormatActor = "agent" | "user";

export type FormatMeta = {
  emoji: string;
  verb: string;
  descriptor: string;
  actor: FormatActor;
};

/**
 * Single source of truth for the format emoji + header copy. The emoji are
 * load-bearing and live ONLY here; every other module references this table so
 * render and selection stay consistent.
 */
export const FORMAT_META: Record<PresentationFormat, FormatMeta> = {
  testing: { emoji: "🧪", verb: "Testing", descriptor: "runs it live", actor: "agent" },
  comparing: { emoji: "⚖️", verb: "Comparing", descriptor: "guardrail / before-after", actor: "agent" },
  inspecting: { emoji: "🔎", verb: "Inspecting", descriptor: "examine the real artifact", actor: "agent" },
  reviewing: { emoji: "📜", verb: "Reviewing", descriptor: "cite an earlier run", actor: "agent" },
  user_led: { emoji: "🙋", verb: "Over to you", descriptor: "needs the human", actor: "user" },
  explaining: { emoji: "💬", verb: "Explaining", descriptor: "description only", actor: "agent" }
};

/**
 * Project a chosen format onto the legacy `delivery_kind` enum. `user_led` has
 * no native delivery_kind, so it falls back to the verification-derived base
 * kind supplied by selection.
 */
export function formatToDeliveryKind(format: PresentationFormat, baseDeliveryKind: DeliveryKind): DeliveryKind {
  switch (format) {
    case "testing":
    case "comparing":
      return "live_demo";
    case "inspecting":
    case "reviewing":
      return "evidence_review";
    case "explaining":
      return "explanation";
    case "user_led":
      return baseDeliveryKind;
  }
}

/** The default format for a verification-derived delivery kind. */
export function defaultFormatForDeliveryKind(kind: DeliveryKind): PresentationFormat {
  switch (kind) {
    case "live_demo":
      return "testing";
    case "evidence_review":
      return "reviewing";
    case "explanation":
      return "explaining";
  }
}

export type ChoosePresentationFormatOptions = {
  baseDeliveryKind: DeliveryKind;
  needsUser?: boolean;
  isContrast?: boolean;
};

/**
 * Pick a presentation format from the base delivery kind plus two affordances:
 * `needsUser` (human-in-the-loop) wins first, then `isContrast` (guardrail /
 * before-after), otherwise the default-for-delivery-kind.
 */
export function choosePresentationFormat(options: ChoosePresentationFormatOptions): PresentationFormat {
  if (options.needsUser) {
    return "user_led";
  }
  if (options.isContrast) {
    return "comparing";
  }
  return defaultFormatForDeliveryKind(options.baseDeliveryKind);
}
