/// Resolves resources by finding explicit paths on a file system and matching globs against the
/// files the code scan reads.
struct ResourceResolver: ResourceResolving {
  let pathFinder: any ExactPathFinding

  func resolve(
    _ resources: [RouteResource],
    among scanned: [WorkspacePath],
    in context: DiscoveryContext,
    listings: inout FolderListings,
  ) -> ResolvedResources {
    var resolved = ResolvedResources()

    for resource in resources {
      switch resource {
      case let .file(path):
        add(
          file: path,
          to: &resolved,
          context: context,
          listings: &listings,
        )
      case let .glob(pattern):
        add(
          glob: pattern,
          among: scanned,
          to: &resolved,
        )
      }
    }

    return resolved
  }

  private func add(
    file path: WorkspacePath,
    to resolved: inout ResolvedResources,
    context: DiscoveryContext,
    listings: inout FolderListings,
  ) {
    do {
      let kind = try pathFinder.find(
        path,
        in: context,
        listings: &listings,
      )

      switch kind {
      case .file, .symlink:
        resolved.files.insert(path)
      case .directory, .other:
        resolved.problems.append(.content(path, .notAFile(kind)))
      }
    } catch {
      resolved.problems.append(.file(path, error))
    }
  }

  /// Matches with `matches`, never `excludes`: a glob names files, and a folder that matches
  /// brings none of its files with it.
  private func add(
    glob pattern: PathPattern,
    among scanned: [WorkspacePath],
    to resolved: inout ResolvedResources,
  ) {
    let matched = scanned.filter { path in
      pattern.matches(path)
    }

    if matched.isEmpty {
      resolved.problems.append(.matchesNothing(pattern))
    }

    resolved.files.formUnion(matched)
  }
}
