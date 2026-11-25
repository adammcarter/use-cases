import Foundation
import UseCasesCore

/// The real viewer, which does something of the test's once a plan has been checked: the moment
/// between the check and the write.
struct SpyPlanViewing: PlanViewing {
  let viewer = OverlayPlanViewer()
  let afterViewing: @Sendable () -> Void

  func view(
    showing plan: WritePlan,
    in root: URL,
  ) throws(PlanWritingError) -> WorkspaceView {
    let view = try viewer.view(
      showing: plan,
      in: root,
    )
    afterViewing()

    return view
  }
}
