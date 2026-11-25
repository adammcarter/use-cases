extension LinkResolver {
  /// The resolver that reads through `fileSystem` and is the real one in everything else.
  init(reading fileSystem: any FileSystemReading) {
    self.init(
      codeScanner: CodeScanner(
        fileSystem: fileSystem,
        markerScanner: MarkerScanner(),
      ),
      markerLinker: MarkerLinker(),
      bindingResolver: ManualBindingResolver(
        fileSystem: fileSystem,
        pathFinder: ExactPathFinder(fileSystem: fileSystem),
        rangeConverter: ManualRangeConverter(),
      ),
      conflictFinder: LinkConflictFinder(),
    )
  }
}
