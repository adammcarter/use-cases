/// What was done and how each change was proven (chapter 21 §7, step 8).
public struct ResultsLayout: Equatable, Sendable {
  public let title: String

  /// Each use case the proposal saved, in the order it lists them.
  public let useCases: [ResultUseCase]

  /// The full ids of the use cases the proposal removed.
  public let removed: [String]

  /// Whether the gate passes, as `status --gate` decides.
  public let gatePasses: Bool

  /// The results.
  public init(
    title: String,
    useCases: [ResultUseCase],
    removed: [String],
    gatePasses: Bool,
  ) {
    self.title = title
    self.useCases = useCases
    self.removed = removed
    self.gatePasses = gatePasses
  }
}
