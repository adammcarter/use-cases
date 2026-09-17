/// How a plan item is delivered, as the legacy `delivery_kind` enum spells it.
public enum DeliveryKind: String, Sendable, Equatable, CaseIterable {
  case liveDemo = "live_demo"
  case evidenceReview = "evidence_review"
  case explanation
}

/// Who acts on a card.
public enum FormatActor: String, Sendable, Equatable {
  case agent
  case user
}

/// The emoji and header copy of one format
/// (packages/core/src/presentation/presentationFormat.ts `FORMAT_META`).
public struct FormatMetadata: Sendable, Equatable {
  public let emoji: String
  public let verb: String
  public let descriptor: String
  public let actor: FormatActor
}

/// The six presentation formats. The agent picks exactly one per item up front
/// and surfaces it with a fixed header and body.
public enum PresentationFormat: String, Sendable, Equatable, CaseIterable {
  case testing
  case comparing
  case inspecting
  case reviewing
  case userLed = "user_led"
  case explaining

  /// The single source of the format emoji and header copy. The emoji are
  /// spelled as scalars so a variation selector cannot be lost in an edit:
  /// Comparing's balance scale is U+2696 followed by U+FE0F.
  public var metadata: FormatMetadata {
    switch self {
    case .testing:
      FormatMetadata(emoji: "\u{1F9EA}", verb: "Testing", descriptor: "runs it live", actor: .agent)
    case .comparing:
      FormatMetadata(
        emoji: "\u{2696}\u{FE0F}",
        verb: "Comparing",
        descriptor: "guardrail / before-after",
        actor: .agent,
      )
    case .inspecting:
      FormatMetadata(
        emoji: "\u{1F50E}",
        verb: "Inspecting",
        descriptor: "examine the real artifact",
        actor: .agent,
      )
    case .reviewing:
      FormatMetadata(
        emoji: "\u{1F4DC}",
        verb: "Reviewing",
        descriptor: "cite an earlier run",
        actor: .agent,
      )
    case .userLed:
      FormatMetadata(
        emoji: "\u{1F64B}",
        verb: "Over to you",
        descriptor: "needs the human",
        actor: .user,
      )
    case .explaining:
      FormatMetadata(
        emoji: "\u{1F4AC}",
        verb: "Explaining",
        descriptor: "description only",
        actor: .agent,
      )
    }
  }

  /// `formatToDeliveryKind`: the legacy projection. `user_led` has no delivery
  /// kind of its own, so it keeps the verification-derived base kind.
  public func deliveryKind(base: DeliveryKind) -> DeliveryKind {
    switch self {
    case .testing, .comparing: .liveDemo
    case .inspecting, .reviewing: .evidenceReview
    case .explaining: .explanation
    case .userLed: base
    }
  }

  /// `defaultFormatForDeliveryKind`.
  public static func defaultFormat(for kind: DeliveryKind) -> PresentationFormat {
    switch kind {
    case .liveDemo: .testing
    case .evidenceReview: .reviewing
    case .explanation: .explaining
    }
  }

  /// `choosePresentationFormat`: a human actor wins, then a contrast, then the
  /// default for the base delivery kind.
  public static func choose(
    baseDeliveryKind: DeliveryKind,
    needsUser: Bool,
    isContrast: Bool,
  ) -> PresentationFormat {
    if needsUser {
      return .userLed
    }
    if isContrast {
      return .comparing
    }
    return defaultFormat(for: baseDeliveryKind)
  }
}
