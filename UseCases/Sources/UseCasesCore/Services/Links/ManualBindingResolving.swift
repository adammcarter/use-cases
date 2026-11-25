/// Resolves the manual bindings written in use cases to files and ranges (chapter 09 §20.1).
protocol ManualBindingResolving: Sendable {
  /// A link for every manual binding that resolves, and a problem for every one that does not.
  ///
  /// The file must be there as the binding spells it, the range must fit it, and a binding into
  /// excluded content or selecting nothing warns.
  func resolve(
    _ useCases: [LoadedUseCase],
    in context: DiscoveryContext,
  ) -> LinkFindings
}
