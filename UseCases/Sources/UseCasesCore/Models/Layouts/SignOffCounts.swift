/// How many use cases of a proposal each tier signs (chapter 21 §6): the ones that change or go,
/// never the untouched.
public struct SignOffCounts: Equatable, Sendable {
  public let critical: Int
  public let core: Int
  public let supporting: Int

  /// Use cases with no value tier: without a tier's permission everything comes to the person.
  public let untiered: Int

  /// The counts.
  public init(
    critical: Int,
    core: Int,
    supporting: Int,
    untiered: Int = 0,
  ) {
    self.untiered = untiered
    self.critical = critical
    self.core = core
    self.supporting = supporting
  }
}
