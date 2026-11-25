/// What `status` knows about a workspace: every use case, worst first then drafts then by id
/// (chapter 16 §9), and what is worth saying about the workspace as a whole.
public struct WorkspaceStatus: Equatable, Sendable {
  /// Every use case, in the order `status` lists them.
  public let useCases: [UseCaseStatus]

  public let warnings: [WorkspaceWarning]

  /// Whether the store holds any sealed run, which is what a checkout that has run nothing lacks
  /// (chapter 16 §9).
  public let hasSealedRuns: Bool

  /// Whether the root says `sign_off: required`, which makes the gate hold a use case whose
  /// promise is not approved (chapter 16 §10).
  public let signOffRequired: Bool

  /// Whether some bridge validation has a run command, which makes `verify --run` the step to
  /// point at and not `verify --start` (chapter 16 §9, §18).
  public let hasRunCommand: Bool

  /// What the results store holds: its runs, its size and how many runs `prune` would remove.
  /// `nil` when the store has no run at all, or when the view asked for does not show it.
  public let store: StoreSummary?

  /// How a person sees a run id of this store (chapter 16 §9).
  public let runIdentifiers: RunIdentifierShortener
}
