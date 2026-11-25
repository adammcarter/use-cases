/// Resolves manual bindings against the file system.
struct ManualBindingResolver: ManualBindingResolving, LocatorPlacing {
  let fileSystem: any FileSystemReading
  let pathFinder: any ExactPathFinding
  let rangeConverter: any ManualRangeConverting

  func resolve(
    _ useCases: [LoadedUseCase],
    in context: DiscoveryContext,
  ) -> LinkFindings {
    var found = LinkFindings.empty
    var files = BoundFiles()

    for site in useCases.flatMap(sites(of:)) {
      resolve(
        site,
        context: context,
        files: &files,
        found: &found,
      )
    }

    return found
  }

  /// Every manual binding of a use case: its own, then those of its routes.
  private func sites(of useCase: LoadedUseCase) -> [BindingSite] {
    let implementation = useCase.definition.bindings.map { binding in
      BindingSite(
        binding: binding,
        identity: LinkIdentity(
          useCase: useCase.identifier,
          route: nil,
          binding: binding.identifier,
        ),
        definition: useCase.file,
      )
    }

    let validation = useCase.definition.routes.flatMap { route in
      route.bindings.map { binding in
        BindingSite(
          binding: binding,
          identity: LinkIdentity(
            useCase: useCase.identifier,
            route: route.identifier,
            binding: binding.identifier,
          ),
          definition: useCase.file,
        )
      }
    }

    return implementation + validation
  }

  private func resolve(
    _ site: BindingSite,
    context: DiscoveryContext,
    files: inout BoundFiles,
    found: inout LinkFindings,
  ) {
    let locator = site.binding.locator

    do {
      let placement = try place(
        locator,
        context: context,
        files: &files,
      )
      let link = ResolvedLink(
        source: .manual,
        identity: site.identity,
        path: locator.file,
        lines: placement.lines,
        span: placement.span,
        contentRanges: placement.span.isEmpty ? [] : [placement.span],
      )

      found.links.append(link)
      found.diagnostics += warnings(
        about: link,
        locator: locator,
        context: context,
      )
    } catch {
      found.diagnostics.append(
        .unresolvedBinding(
          error,
          identity: site.identity,
          path: locator.file,
          definedIn: site.definition,
        ),
      )
    }
  }

  func place(
    _ locator: ManualLocator,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(ManualBindingProblem) -> ManualPlacement {
    let content = try content(
      of: locator.file,
      context: context,
      files: &files,
    )

    do {
      return try rangeConverter.place(
        locator.range,
        in: content,
      )
    } catch {
      throw .range(error)
    }
  }

  /// What the file holds. A symlink holds the text it points with, never what is there.
  private func content(
    of file: WorkspacePath,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(ManualBindingProblem) -> ManualContent {
    if let known = files.content(of: file) {
      return known
    }

    let kind: FileEntryKind

    do {
      kind = try pathFinder.find(
        file,
        in: context,
        listings: &files.listings,
      )
    } catch {
      throw .path(error)
    }

    let bytes = try bytes(
      of: file,
      kind: kind,
      context: context,
    )
    let content = ManualContent(bytes: bytes)
    files.remember(
      content,
      of: file,
    )

    return content
  }

  private func bytes(
    of file: WorkspacePath,
    kind: FileEntryKind,
    context: DiscoveryContext,
  ) throws(ManualBindingProblem) -> [UInt8] {
    let location = context.url(for: file)

    do {
      switch kind {
      case .file:
        return try fileSystem.readBytes(at: location)
      case .symlink:
        return try Array(fileSystem.targetText(ofSymlinkAt: location).utf8)
      case .directory, .other:
        break
      }
    } catch {
      throw .unreadable(error)
    }

    throw .notAFile(kind)
  }
}
