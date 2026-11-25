import Foundation
import UseCasesCore

/// The real aborter, which does something of the test's after it has closed the run.
struct SpyVerifyAborter: VerifyAborting {
  let aborter = VerifyAborter()
  let afterAborting: @Sendable () -> Void

  func abort(
    _ request: VerifyAbortRequest,
    in root: URL,
  ) async throws(VerifyError) -> AbortedVerifyRun {
    let aborted = try await aborter.abort(
      request,
      in: root,
    )
    afterAborting()

    return aborted
  }
}
