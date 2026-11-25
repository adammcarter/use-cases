/// Computes route fingerprints from the workspace as it is on disk: links read from the real
/// bytes, resources expanded over the files the code scan reads, and the encoding left to
/// ``RouteFingerprinting``.
public struct RouteFingerprintComputer: RouteFingerprintComputing {
  let scanLister: any ScannedFileListing
  let resourceResolver: any ResourceResolving
  let contentReader: any FileContentReading
  let linkBuilder: any LinkContributionBuilding
  let fingerprinter: any RouteFingerprinting
  let hasher: any Hashing

  /// Makes the computer that reads the real file system.
  public init() {
    self.init(fileSystem: LocalFileSystem())
  }

  /// Makes the computer that reads this file system.
  init(fileSystem: any FileSystemReading) {
    let reader = FileContentReader(fileSystem: fileSystem)

    self.init(
      scanLister: ScannedFileLister(fileSystem: fileSystem),
      resourceResolver: ResourceResolver(pathFinder: ExactPathFinder(fileSystem: fileSystem)),
      contentReader: reader,
      linkBuilder: LinkContributionBuilder(reader: reader),
      fingerprinter: RouteFingerprinter(),
    )
  }

  init(
    scanLister: any ScannedFileListing,
    resourceResolver: any ResourceResolving,
    contentReader: any FileContentReading,
    linkBuilder: any LinkContributionBuilding,
    fingerprinter: any RouteFingerprinting,
    hasher: any Hashing = SHA256Hasher(),
  ) {
    self.hasher = hasher
    self.scanLister = scanLister
    self.resourceResolver = resourceResolver
    self.contentReader = contentReader
    self.linkBuilder = linkBuilder
    self.fingerprinter = fingerprinter
  }

  public func fingerprints(
    of workspace: LoadedWorkspace,
    links: LinkResolution,
  ) -> RouteFingerprints {
    let run = FreshnessRun(
      workspace: workspace,
      linkedFiles: Set(links.links.map(\.path)),
    )
    var caches = FreshnessCaches()
    let resources = resolveResources(
      in: run,
      caches: &caches,
    )
    var errors = links.errors + resources.diagnostics

    guard !links.isInvalid else {
      return RouteFingerprints(
        routes: [],
        errors: errors,
        warnings: resources.warnings,
      )
    }

    let grouped = GroupedLinks(links.links)
    var routes: [LiveRouteFingerprint] = []

    for useCase in workspace.useCases where useCase.definition.authoredState == .ready {
      let found = fingerprints(
        of: useCase,
        in: run,
        links: grouped,
        resources: resources,
        caches: &caches,
      )

      routes += found.routes
      errors += found.diagnostics
    }

    return RouteFingerprints(
      routes: routes,
      errors: errors,
      warnings: resources.warnings,
      fileDigests: fileDigests(of: caches),
    )
  }

  /// The SHA-256 of the exact bytes of every file the run read, links and resources alike,
  /// sorted by path. It is what `verify --start` keeps so that a later "code changed during the
  /// run" can name the files that moved.
  private func fileDigests(of caches: FreshnessCaches) -> [FileDigest] {
    let held = caches.bytes.map { path, bytes in
      FileDigest(
        path: path.text,
        digest: hasher.sha256Hex(of: bytes),
      )
    }
    let streamed = caches.streamedDigests.map { path, digest in
      FileDigest(
        path: path.text,
        digest: digest,
      )
    }

    return (held + streamed).sorted { left, right in
      left.path.precedesExactly(right.path)
    }
  }
}
