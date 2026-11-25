/// Begins a run of edits over a workspace: one sequence for each batch or sign-off.
protocol UseCaseEditSequenceMaking: Sendable {
  /// A sequence that has made no edit yet.
  ///
  /// - Parameter workspace: The workspace as it is.
  func sequence(for workspace: LoadedWorkspace) -> any UseCaseEditSequencing
}
