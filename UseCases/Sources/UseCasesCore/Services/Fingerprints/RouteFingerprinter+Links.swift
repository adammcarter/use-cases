extension RouteFingerprinter {
  /// One entry per binding, sorted by binding id (§89.5). Content mode writes the regions'
  /// contents sorted by identity, with duplicates kept; content-and-locator mode writes each
  /// region's locator and content sorted by file and offsets.
  func linksValue(
    of links: [LinkContribution],
    policy: FreshnessPolicy,
  ) throws(FingerprintingError) -> CanonicalValue {
    let sorted = links.sorted { lhs, rhs in
      lhs.binding.text.precedesExactly(rhs.binding.text)
    }

    for (index, link) in sorted.enumerated() {
      if link.regions.isEmpty {
        throw .bindingWithoutRegions(link.binding.text)
      }

      if index > 0, link.binding.text.isExactlyEqual(to: sorted[index - 1].binding.text) {
        throw .duplicateBinding(link.binding.text)
      }
    }

    return .array(
      sorted.map { link in
        entryValue(
          of: link,
          policy: policy,
        )
      },
    )
  }

  /// One entry per resource file, sorted by path. A file reached twice with the same content is
  /// one entry (§89.6).
  func resourcesValue(
    of resources: [ResourceContribution],
  ) throws(FingerprintingError) -> CanonicalValue {
    let sorted = resources.sorted { lhs, rhs in
      lhs.file < rhs.file
    }
    var kept: [ResourceContribution] = []

    for resource in sorted {
      guard let last = kept.last, last.file == resource.file else {
        kept.append(resource)
        continue
      }

      guard last.content == resource.content else {
        throw .conflictingResource(resource.file.text)
      }
    }

    return .array(
      kept.map { resource in
        .members([
          "file": .string(resource.file.text),
          "content": resource.content.canonical,
        ])
      },
    )
  }

  private func entryValue(
    of link: LinkContribution,
    policy: FreshnessPolicy,
  ) -> CanonicalValue {
    switch policy.bindingIdentity {
    case .content:
      contentEntry(of: link)
    case .contentAndLocator:
      locatorEntry(of: link)
    }
  }

  private func contentEntry(of link: LinkContribution) -> CanonicalValue {
    let contents = link.regions.map(\.content).sorted { lhs, rhs in
      lhs.precedes(rhs)
    }

    return .members([
      "id": .string(link.binding.text),
      "regions": .array(
        contents.map { content in
          content.canonical
        },
      ),
    ])
  }

  private func locatorEntry(of link: LinkContribution) -> CanonicalValue {
    let regions = link.regions.sorted { lhs, rhs in
      lhs.precedesByLocator(rhs)
    }

    return .members([
      "id": .string(link.binding.text),
      "kind": .string(link.kind.rawValue),
      "regions": .array(
        regions.map { region in
          .members([
            "locator": region.locator.canonical,
            "content": region.content.canonical,
          ])
        },
      ),
    ])
  }
}
