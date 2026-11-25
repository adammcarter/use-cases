/// Resolves links from the file system: scans the code for markers, resolves the manual bindings,
/// and checks that the links can all stand.
public struct LinkResolver: LinkResolving {
  private let codeScanner: any CodeScanning
  private let markerLinker: any MarkerLinking
  private let bindingResolver: any ManualBindingResolving
  private let conflictFinder: any LinkConflictFinding

  /// Makes the resolver that reads the real file system.
  public init() {
    let fileSystem = LocalFileSystem()

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

  init(
    codeScanner: any CodeScanning,
    markerLinker: any MarkerLinking,
    bindingResolver: any ManualBindingResolving,
    conflictFinder: any LinkConflictFinding,
  ) {
    self.codeScanner = codeScanner
    self.markerLinker = markerLinker
    self.bindingResolver = bindingResolver
    self.conflictFinder = conflictFinder
  }

  /// Resolves the links of `workspace`: every marker region in the code that names a known use
  /// case, every manual binding and every link a transformer returned, with the problems and
  /// warnings about them (chapter 09 §20).
  public func resolveLinks(
    in workspace: LoadedWorkspace,
    including transformed: TransformedLinks,
  ) -> LinkResolution {
    let context = workspace.discoveryContext
    let scan = codeScanner.scan(
      workspace,
      excluding: context,
    )
    let marked = markerLinker.links(
      for: scan.regions,
      among: workspace.useCases,
    )
    let bound = bindingResolver.resolve(
      workspace.useCases,
      in: context,
    )

    let links = marked.links + bound.links + transformed.findings.links
    let conflicts = conflictFinder.conflicts(
      among: links,
      definitions: Dictionary(
        workspace.useCases.map { useCase in
          (useCase.identifier, useCase.file)
        },
        uniquingKeysWith: { first, _ in
          first
        },
      ),
    )

    return LinkResolution(
      links: links,
      diagnostics: workspace.warnings + workspace.heldProblems + scan.diagnostics + marked
        .diagnostics + bound.diagnostics
        + transformed.findings.diagnostics + conflicts,
    )
  }
}
