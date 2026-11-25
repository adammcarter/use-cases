/// Checks a returned link in the order a person would: whose it is, then where it points.
struct TransformerLinkChecker: TransformerLinkChecking {
  private let placer: any LocatorPlacing

  init(placer: any LocatorPlacing) {
    self.placer = placer
  }

  func resolve(
    _ link: TransformerLink,
    from name: String,
    among targets: LinkTargets,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(TransformerError) -> ResolvedLink {
    do {
      let identity = try identity(
        of: link,
        among: targets,
      )

      return try place(
        link,
        as: identity,
        context: context,
        files: &files,
      )
    } catch {
      throw .badLink(
        name: name,
        link: link.text,
        problem: error,
      )
    }
  }

  /// The use case, route and binding the link names, all of which must exist.
  private func identity(
    of link: TransformerLink,
    among targets: LinkTargets,
  ) throws(TransformerLinkProblem) -> LinkIdentity {
    guard let useCaseText = link.useCase else {
      throw .missingMember("use_case")
    }

    guard let useCase = targets.useCase(named: useCaseText) else {
      throw .unknownUseCase(useCaseText)
    }

    guard let role = link.role else {
      throw .missingMember("role")
    }

    guard let bindingText = link.binding else {
      throw .missingMember("binding")
    }

    guard let binding = try? BindingIdentifier(validating: bindingText) else {
      throw .invalidBinding(bindingText)
    }

    return try LinkIdentity(
      useCase: useCase.identifier,
      route: route(
        of: link,
        role: role,
        in: useCase,
      ),
      binding: binding,
    )
  }

  /// A validation link names one of the use case's routes; an implementation link names none.
  private func route(
    of link: TransformerLink,
    role: String,
    in useCase: LoadedUseCase,
  ) throws(TransformerLinkProblem) -> RouteIdentifier? {
    guard let kind = LinkRole(rawValue: role) else {
      throw .unknownRole(role)
    }

    switch kind {
    case .implementation:
      if let route = link.route {
        throw .implementationHasRoute(route)
      }

      return nil
    case .validation:
      guard let route = link.route else {
        throw .validationNeedsRoute
      }

      guard
        let known = useCase.definition.routes.first(where: { candidate in
          candidate.identifier.text == route
        })
      else {
        throw .unknownRoute(
          route: route,
          useCase: useCase.identifier.text,
        )
      }

      return known.identifier
    }
  }

  /// Where the link points: a file inside the workspace that the scan reads, and lines inside it.
  private func place(
    _ link: TransformerLink,
    as identity: LinkIdentity,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(TransformerLinkProblem) -> ResolvedLink {
    guard let fileText = link.file else {
      throw .missingMember("file")
    }

    let path = try path(of: fileText)

    if let exclusion = context.exclusion(covering: path) {
      throw .fileExcluded(exclusion)
    }

    let locator = try ManualLocator(
      file: path,
      range: manualRange(of: link),
    )
    let placement: ManualPlacement

    do {
      placement = try placer.place(
        locator,
        context: context,
        files: &files,
      )
    } catch {
      throw problem(
        of: error,
        path: path,
      )
    }

    return ResolvedLink(
      source: .transformer,
      identity: identity,
      path: path,
      lines: placement.lines,
      span: placement.span,
      contentRanges: placement.span.isEmpty ? [] : [placement.span],
    )
  }

  private func path(of text: String) throws(TransformerLinkProblem) -> WorkspacePath {
    let path: WorkspacePath

    do {
      path = try WorkspacePath(validating: text)
    } catch {
      throw .fileOutsideProject(error)
    }

    guard !path.isRoot else {
      throw .file(
        .notAFile(.directory),
        path: path,
      )
    }

    return path
  }

  /// A range is both lines or neither; a link that names no range covers the whole file.
  private func manualRange(of link: TransformerLink) throws(TransformerLinkProblem)
    -> ManualRange?
  {
    guard let range = link.range else {
      return nil
    }

    guard
      let start = range.start,
      let end = range.end,
      let first = try? SourcePosition(line: start),
      let last = try? SourcePosition(line: end)
    else {
      throw .rangeNotLines
    }

    return ManualRange(
      start: first,
      end: last,
    )
  }

  private func problem(
    of error: ManualBindingProblem,
    path: WorkspacePath,
  ) -> TransformerLinkProblem {
    switch error {
    case let .range(rangeError):
      .range(
        rangeError,
        path: path,
      )
    case .path, .notAFile, .unreadable:
      .file(
        error,
        path: path,
      )
    }
  }
}
