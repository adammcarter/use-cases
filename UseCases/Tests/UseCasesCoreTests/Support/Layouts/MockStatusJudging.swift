@testable import UseCasesCore

/// A judge that answers with the status the test decides, whatever the workspace holds.
struct MockStatusJudging: StatusJudging {
  private let outcome: Result<WorkspaceStatus, StatusJudgingError>

  init(_ status: WorkspaceStatus) {
    outcome = .success(status)
  }

  init(failing error: StatusJudgingError) {
    outcome = .failure(error)
  }

  func judge(
    _: LoadedWorkspace,
    links _: LinkResolution,
  ) throws(StatusJudgingError) -> WorkspaceStatus {
    try outcome.get()
  }
}
