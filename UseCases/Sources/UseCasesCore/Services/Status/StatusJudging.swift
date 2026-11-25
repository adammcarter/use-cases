/// Judges every use case of a workspace against the results store (chapter 07, chapter 12 §27):
/// what `use-cases status` and its gate are built on.
public protocol StatusJudging: Sendable {
  /// The status of every use case, worst first, then drafts, then by id. Reads the files links
  /// point into and the results store; writes nothing.
  ///
  /// A READY use case's routes are judged at their fingerprints as the workspace is on disk now.
  /// The use case takes the worst state among its gating routes (chapter 07); a route that does
  /// not gate is reported and never decides.
  ///
  /// - Parameters:
  ///   - workspace: A workspace that loaded.
  ///   - links: What link resolution found in that workspace.
  /// - Throws: ``StatusJudgingError`` when the workspace is INVALID for a reason only
  ///   fingerprinting finds, or when the store is damaged.
  func judge(
    _ workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(StatusJudgingError) -> WorkspaceStatus

  /// As `judge(_:links:)`, and with `measuringStore` the store's runs, size and superseded runs
  /// too (chapter 16 §9), which only the views that show them pay for.
  func judge(
    _ workspace: LoadedWorkspace,
    links: LinkResolution,
    measuringStore: Bool,
  ) throws(StatusJudgingError) -> WorkspaceStatus
}

public extension StatusJudging {
  /// A judge that has no store line to give judges as it always does.
  func judge(
    _ workspace: LoadedWorkspace,
    links: LinkResolution,
    measuringStore _: Bool,
  ) throws(StatusJudgingError) -> WorkspaceStatus {
    try judge(
      workspace,
      links: links,
    )
  }
}
