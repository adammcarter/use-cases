import Foundation

/// Shows a plan over the real file system, in memory.
public struct OverlayPlanViewer: PlanViewing {
  private let fileSystem: any FileSystemReading
  private let preflight: any ChangeChecking

  /// Makes the viewer that reads the real file system.
  public init() {
    self.init(fileSystem: LocalFileSystem())
  }

  init(fileSystem: any FileSystemReading) {
    self.init(
      fileSystem: fileSystem,
      preflight: PlanPreflight(fileSystem: fileSystem),
    )
  }

  /// - Parameters:
  ///   - fileSystem: What the plan is laid over.
  ///   - preflight: Refuses a change that cannot be made where it is asked.
  init(
    fileSystem: any FileSystemReading,
    preflight: any ChangeChecking,
  ) {
    self.fileSystem = fileSystem
    self.preflight = preflight
  }

  public func view(
    showing plan: WritePlan,
    in root: URL,
  ) throws(PlanWritingError) -> WorkspaceView {
    for change in plan.changes {
      try preflight.check(
        change,
        in: root,
      )
    }

    let planned = PlannedFileSystem(
      base: fileSystem,
      plan: plan,
      root: root,
    )

    return WorkspaceView(
      loader: WorkspaceLoader(reading: planned),
      resolver: LinkResolver(reading: planned),
    )
  }
}
