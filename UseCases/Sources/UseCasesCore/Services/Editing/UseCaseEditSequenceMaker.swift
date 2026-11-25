/// Begins runs of edits that read the files from a file system.
struct UseCaseEditSequenceMaker: UseCaseEditSequenceMaking {
  private let fileSystem: any FileSystemReading

  /// - Parameter fileSystem: What the files are read from, below the edits.
  init(fileSystem: any FileSystemReading = LocalFileSystem()) {
    self.fileSystem = fileSystem
  }

  func sequence(for workspace: LoadedWorkspace) -> any UseCaseEditSequencing {
    UseCaseEditSequence(
      workspace: workspace,
      fileSystem: fileSystem,
    )
  }
}
