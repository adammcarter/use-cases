extension ProposalChange {
  /// The line of a use case the proposal names.
  ///
  /// - Parameters:
  ///   - change: The use case set against the workspace.
  ///   - youSee: What the proposal says the person will see of it, if anything.
  init(
    change: ResolvedChange,
    youSee: String?,
  ) {
    self.init(
      useCase: change.identifier,
      fit: change.fit,
      title: change.shown.title,
      tier: change.shown.valueTier?.rawValue,
      youSee: youSee,
    )
  }
}
