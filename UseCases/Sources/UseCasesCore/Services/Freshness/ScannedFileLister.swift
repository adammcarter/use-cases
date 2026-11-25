/// Names every file the code scan reads, by asking the one walk the scan itself uses.
struct ScannedFileLister: ScannedFileListing {
  let walker: any CodeFileWalking

  /// Lists with the walk of the real code scan on this file system.
  init(fileSystem: any FileSystemReading) {
    walker = CodeFileWalker(fileSystem: fileSystem)
  }

  func files(
    in workspace: LoadedWorkspace,
    excluding context: DiscoveryContext,
  ) -> ScannedFiles {
    let walk = walker.walk(
      workspace,
      excluding: context,
    )

    return ScannedFiles(
      files: walk.files.map(\.path).sorted(),
      diagnostics: walk.diagnostics.filter { diagnostic in
        diagnostic.severity == .error
      },
    )
  }
}
