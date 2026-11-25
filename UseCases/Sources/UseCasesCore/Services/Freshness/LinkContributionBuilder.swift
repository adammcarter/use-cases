/// Builds contributions from the bytes of the files the links point into, reading each file once
/// per run (through the run's shared cache).
struct LinkContributionBuilder: LinkContributionBuilding {
  let reader: any FileContentReading

  func contributions(
    of links: [ResolvedLink],
    in run: FreshnessRun,
    caches: inout FreshnessCaches,
  ) -> LinkContributions {
    var found = LinkContributions(
      contributions: [],
      diagnostics: [],
    )
    let groups = Dictionary(grouping: links) { link in
      link.identity.binding
    }

    for (binding, group) in groups {
      guard let first = group.first else {
        continue
      }

      var regions: [LinkRegionContribution] = []

      for link in group {
        guard let region = region(of: link, in: run, caches: &caches, found: &found) else {
          continue
        }

        regions.append(region)
      }

      if regions.count == group.count {
        found.contributions.append(
          LinkContribution(
            binding: binding,
            kind: LinkContributionKind(source: first.source),
            regions: regions,
          ),
        )
      }
    }

    return found
  }

  private func region(
    of link: ResolvedLink,
    in run: FreshnessRun,
    caches: inout FreshnessCaches,
    found: inout LinkContributions,
  ) -> LinkRegionContribution? {
    let bytes: [UInt8]

    do {
      bytes = try caches.bytes(
        of: link.path,
        using: reader,
        in: run.context,
      )
    } catch {
      found.diagnostics.append(.linkedFileUnreadable(link, because: error))
      return nil
    }

    do {
      return try LinkRegionContribution(
        link: link,
        fileBytes: bytes,
        referencer: run.referencer,
      )
    } catch {
      found.diagnostics.append(.linkedRegionOutsideFile(link))
      return nil
    }
  }
}
