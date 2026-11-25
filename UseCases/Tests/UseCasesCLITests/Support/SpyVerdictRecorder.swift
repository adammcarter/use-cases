import Foundation
import UseCasesCore

/// The real recorder, which does something of the test's after it has fingerprinted the route,
/// while it writes, and after it has written.
struct SpyVerdictRecorder: VerdictRecording {
  let recorder = VerdictRecorder()
  let afterPlanning: @Sendable () -> Void
  let whileCommitting: @Sendable () -> Void
  let afterCommitting: @Sendable () -> Void

  func plan(
    _ request: RecordRequest,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
  ) throws(RecordingError) -> RecordPlan {
    let plan = try recorder.plan(
      request,
      in: workspace,
      links: links,
    )
    afterPlanning()

    return plan
  }

  func offers(in workspace: LoadedWorkspace) -> [RecordOffer] {
    recorder.offers(in: workspace)
  }

  func checkAttachments(at locations: [URL]) throws(RecordingError) {
    try recorder.checkAttachments(at: locations)
  }

  func commit(_ plan: RecordPlan) throws(RecordingError) -> RecordedRun {
    whileCommitting()

    let run = try recorder.commit(plan)
    afterCommitting()

    return run
  }
}
