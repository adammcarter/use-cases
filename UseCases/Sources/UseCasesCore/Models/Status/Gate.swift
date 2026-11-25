/// The gate's answer: does anything block? (chapter 16 §10). A use case is in at most one list,
/// in the order `status` lists use cases.
public struct Gate: Equatable, Sendable {
  /// Whether `--strict` was asked: incomplete, unverified and unapproved use cases block.
  public let isStrict: Bool

  public let blocking: [GateEntry]

  public let warning: [GateEntry]

  /// Whether nothing blocks. Warnings do not stop it.
  public var passed: Bool {
    blocking.isEmpty
  }
}
