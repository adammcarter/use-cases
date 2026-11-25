/// Looks the use case and route of each marker up among the loaded use cases.
struct MarkerLinker: MarkerLinking {
  func links(
    for regions: [FileRegion],
    among useCases: [LoadedUseCase],
  ) -> LinkFindings {
    let known = Dictionary(
      useCases.map { useCase in
        (useCase.identifier, useCase)
      },
      uniquingKeysWith: { first, _ in
        first
      },
    )

    var found = LinkFindings.empty

    for placed in regions {
      let target = placed.region.target

      guard let useCase = known[target.useCase] else {
        found.diagnostics.append(.markerForUnknownUseCase(placed))
        continue
      }

      if let route = target.route, !has(route, in: useCase) {
        found.diagnostics.append(.markerForUnknownRoute(placed))
        continue
      }

      found.links.append(link(for: placed))
    }

    return found
  }

  private func has(
    _ route: RouteIdentifier,
    in useCase: LoadedUseCase,
  ) -> Bool {
    useCase.definition.routes.contains { candidate in
      candidate.identifier == route
    }
  }

  private func link(for placed: FileRegion) -> ResolvedLink {
    let target = placed.region.target

    return ResolvedLink(
      source: .marker,
      identity: LinkIdentity(
        useCase: target.useCase,
        route: target.route,
        binding: target.binding,
      ),
      path: placed.file,
      lines: placed.region.lines,
      span: placed.region.byteRange,
      contentRanges: placed.region.contentRanges,
    )
  }
}
