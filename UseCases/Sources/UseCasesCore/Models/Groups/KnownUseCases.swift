/// The use cases a groups file is resolved against (chapter 03 "DRAFT and READY membership").
enum KnownUseCases: Equatable, Sendable {
  /// Every use case loaded, DRAFT and READY alike.
  case all([UseCaseIdentifier])

  /// Some use case file could not be read, so the set is not safe to resolve against: the groups
  /// file is checked for its structure only.
  case uncertain
}
