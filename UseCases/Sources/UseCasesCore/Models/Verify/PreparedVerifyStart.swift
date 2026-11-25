import Foundation

/// A start point that has read everything it needs and written nothing (chapter 13 §5): what
/// ``VerifyStarting/commit(_:)`` publishes.
public struct PreparedVerifyStart: Sendable {
  /// What `start.json` will hold; `nil` when the bridge settings select no validation.
  let draft: StartDraft?

  /// The validations the run reads, in the order of the bridge settings.
  let selected: [BridgeValidation]

  /// The workspace root.
  let root: URL

  /// The runs that were open beside this one.
  let others: OpenRuns

  /// Whether committing writes nothing, because no validation is set up.
  public var writesNothing: Bool {
    draft == nil
  }
}
