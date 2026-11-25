import Foundation
@testable import UseCasesCore

/// A viewer that shows the workspace as it is, whatever the plan: the check then finds a
/// workspace that does not hold what the change meant it to.
struct UnchangedPlanViewer: PlanViewing {
  func view(
    showing _: WritePlan,
    in root: URL,
  ) throws(PlanWritingError) -> WorkspaceView {
    try OverlayPlanViewer().view(
      showing: WritePlan(changes: []),
      in: root,
    )
  }
}
