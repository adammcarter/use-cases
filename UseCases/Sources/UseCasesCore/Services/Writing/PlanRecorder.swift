import Foundation

/// Records what the files of a plan hold by reading them.
public struct PlanRecorder: PlanRecording {
  private let fileSystem: any FileSystemReading

  /// Makes the recorder that reads the real file system.
  public init() {
    self.init(fileSystem: LocalFileSystem())
  }

  init(fileSystem: any FileSystemReading) {
    self.fileSystem = fileSystem
  }

  public func recording(_ writes: [FolderWrite]) -> [FolderWrite] {
    writes.map { write in
      FolderWrite(
        folder: write.folder,
        plan: WritePlan(
          changes: write.plan.changes.map { change in
            recording(
              change,
              in: write.folder,
            )
          },
        ),
      )
    }
  }

  private func recording(
    _ change: FileChange,
    in folder: URL,
  ) -> FileChange {
    guard change.action != .create, change.expected == nil else {
      return change
    }

    guard let held = try? fileSystem.readBytes(at: folder.appendingPathComponent(change.path))
    else {
      return change
    }

    return change.expecting(held)
  }
}
