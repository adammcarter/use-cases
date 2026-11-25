import Foundation

/// A request that was checked against the workspace and fingerprinted, and that nothing has yet
/// written (chapter 13 §12 steps 2 and 3). Committing it writes the run.
public struct RecordPlan: Equatable, Sendable {
  /// The full id of the use case the request named.
  public let useCase: String

  /// The id of the route the request named.
  public let route: String

  /// The route's fingerprint now.
  public let fingerprint: String

  /// The verdict, as the store spells it.
  public let status: String

  let workspace: URL
  let result: PlannedResult

  /// What is stored about the verdict, before the time is known.
  struct PlannedResult: Equatable, Sendable {
    let useCase: UseCaseIdentifier
    let route: RouteIdentifier
    let fingerprint: RouteFingerprint
    let verdict: Verdict
    let message: String?
    let attachments: SpooledAttachments
  }

  init(
    workspace: URL,
    result: PlannedResult,
  ) {
    self.workspace = workspace
    self.result = result
    useCase = result.useCase.text
    route = result.route.text
    fingerprint = result.fingerprint.text
    status = result.verdict.rawValue
  }
}
