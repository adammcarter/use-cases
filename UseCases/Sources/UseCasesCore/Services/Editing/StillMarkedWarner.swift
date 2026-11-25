/// Lists the markers in code that still name use cases that are taken out. A manual binding goes
/// with its use case, and a link a transformer returns is the transformer's to make again, so
/// only markers are listed.
struct StillMarkedWarner: StillMarkedWarning {
  func warnings(
    for identifiers: [String],
    in links: [ResolvedLink],
  ) -> [String] {
    var regions: [MarkedRegion] = []

    for link in links where link.source == .marker {
      guard identifiers
        .contains(where: { identifier in link.useCase.isExactlyEqual(to: identifier) })
      else {
        continue
      }

      let region = MarkedRegion(
        file: link.file,
        start: link.startLine,
        end: link.endLine,
        useCase: link.useCase,
      )

      if !regions.contains(region) {
        regions.append(region)
      }
    }

    return regions.sorted().map { region in
      "\(region.file):\(region.lines) is still marked for \(region.useCase)"
    }
  }
}
