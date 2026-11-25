extension [UseCaseExpectation] {
  /// What the workspace holds that none of the expectations meant: the first they do not hold,
  /// in words; `nil` when it holds every one.
  func divergence(in workspace: LoadedWorkspace) -> String? {
    for expectation in self {
      if let divergence = expectation.divergence(in: workspace) {
        return divergence
      }
    }

    return nil
  }
}
