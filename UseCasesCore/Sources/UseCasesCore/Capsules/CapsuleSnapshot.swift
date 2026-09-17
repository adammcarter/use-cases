/// Everything loading `demo-capsules/` found (`CapsuleSnapshot`).
public struct CapsuleSnapshot: Sendable, Equatable {
  /// No diagnostic is an error.
  public let isComplete: Bool
  /// Every rejected entry in walk order, then every file that was read, in
  /// walk order.
  public let files: [CapsuleFileResult]
  public let capsules: [LoadedDemoCapsule]
  public let diagnostics: [Diagnostic]

  public init(
    files: [CapsuleFileResult],
    capsules: [LoadedDemoCapsule],
    diagnostics: [Diagnostic],
  ) {
    isComplete = diagnostics.allSatisfy { diagnostic in
      diagnostic.severity != .error
    }
    self.files = files
    self.capsules = capsules
    self.diagnostics = diagnostics
  }

  /// `{ schema_version, complete, files, capsules, diagnostics }`.
  public var jsonValue: JSONValue {
    .object(JSONObject([
      ("schema_version", .number(1)),
      ("complete", .bool(isComplete)),
      ("files", .array(files.map(\.jsonValue))),
      ("capsules", .array(capsules.map(\.jsonValue))),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
    ]))
  }
}
