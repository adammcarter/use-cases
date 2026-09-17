import Foundation

/// Which kind of plan is being prepared.
public enum PresentationMode: String, Sendable, Equatable, CaseIterable {
  case showcase
  case walkthrough
}

/// What a caller asks a plan for (`PresentationPlanRequest`).
///
/// Numbers are doubles because the TypeScript takes whatever number a flag or
/// tool argument carried: a fractional or negative limit is applied as is, a
/// zero timebox falls back to the profile's, and a zero item cap does not.
public struct PresentationPlanRequest: Sendable, Equatable {
  public var audience: String
  public var timeboxSeconds: Double
  /// Nil takes the profile's default cap.
  public var maxItems: Double?
  /// Nil is `"unknown"`, which every row matches.
  public var hostSurface: String?
  public var changedPaths: [String]
  /// Empty requests every row.
  public var requestedUseCaseIdentifiers: [String]
  /// Nil reads the clock.
  public var generatedAt: String?
  /// Nil is ``generatedAt``.
  public var freshnessEvaluatedAt: String?
  public var isStrict: Bool

  public init(
    audience: String,
    timeboxSeconds: Double,
    maxItems: Double? = nil,
    hostSurface: String? = nil,
    changedPaths: [String] = [],
    requestedUseCaseIdentifiers: [String] = [],
    generatedAt: String? = nil,
    freshnessEvaluatedAt: String? = nil,
    isStrict: Bool = false,
  ) {
    self.audience = audience
    self.timeboxSeconds = timeboxSeconds
    self.maxItems = maxItems
    self.hostSurface = hostSurface
    self.changedPaths = changedPaths
    self.requestedUseCaseIdentifiers = requestedUseCaseIdentifiers
    self.generatedAt = generatedAt
    self.freshnessEvaluatedAt = freshnessEvaluatedAt
    self.isStrict = isStrict
  }
}

/// A selection profile: the mode it plans for and its defaults.
public struct SelectionProfile: Sendable, Equatable {
  public let identifier: String
  public let mode: PresentationMode
  public let defaultTimeboxSeconds: Double
  public let defaultMaxItems: Double
  public let fallbackEstimateSeconds: Double

  /// `SHOWCASE_PROFILE`.
  public static let showcase = SelectionProfile(
    identifier: "showcase-v1",
    mode: .showcase,
    defaultTimeboxSeconds: 600,
    defaultMaxItems: 5,
    fallbackEstimateSeconds: 120,
  )

  /// `WALKTHROUGH_PROFILE`.
  public static let walkthrough = SelectionProfile(
    identifier: "walkthrough-v1",
    mode: .walkthrough,
    defaultTimeboxSeconds: 1800,
    defaultMaxItems: 12,
    fallbackEstimateSeconds: 180,
  )

  /// The profile object as the TypeScript hashes it for
  /// `selection_profile.digest`: its own camelCase member names.
  var digestValue: JSONValue {
    .object(JSONObject([
      ("id", .string(identifier)),
      ("mode", .string(mode.rawValue)),
      ("defaultTimeboxSeconds", .number(defaultTimeboxSeconds)),
      ("defaultMaxItems", .number(defaultMaxItems)),
      ("fallbackEstimateSeconds", .number(fallbackEstimateSeconds)),
    ]))
  }
}

/// The clock a plan reads when the request carries no `generatedAt`: the
/// TypeScript's `new Date()`. The one externality planning has.
public protocol PresentationClock: Sendable {
  /// Milliseconds since the epoch, whole, as `Date.now()` answers.
  func milliseconds() -> Double
}

/// The real clock.
public struct SystemPresentationClock: PresentationClock {
  /// The process's own clock.
  public init() {}

  public func milliseconds() -> Double {
    (Date().timeIntervalSince1970 * 1000).rounded(.down)
  }
}
