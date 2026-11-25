/// The conflicts between links, with their wording in one place (chapter 08 "Rules for every
/// link").
extension Diagnostic {
  /// A binding that more than one source names (chapter 08 "Binding ID uniqueness"): INVALID. It
  /// is filed under the definition file of its use case.
  static func bindingClaimedTwice(
    _ identity: LinkIdentity,
    manual: ResolvedLink?,
    markers: [ResolvedLink],
    transformed: [ResolvedLink],
    definedIn definition: WorkspacePath,
  ) -> Diagnostic {
    var claimants: [String] = []

    if let manual {
      claimants.append("a manual binding (\(manual.path))")
    }

    if !markers.isEmpty {
      claimants.append("markers (\(places(of: markers)))")
    }

    if !transformed.isEmpty {
      claimants.append("a links transformer (\(places(of: transformed)))")
    }

    return Diagnostic(
      file: definition,
      position: nil,
      code: .bindingClaimedTwice,
      severity: .error,
      message: "\(identity.subject) is claimed by \(claimants.joined(separator: " and by ")); "
        + "one binding has one source",
    )
  }

  private static func places(of links: [ResolvedLink]) -> String {
    links
      .map { link in
        "\(link.path):\(link.startLine)"
      }
      .sorted { lhs, rhs in
        lhs.precedesExactly(rhs)
      }
      .joined(separator: ", ")
  }

  /// Two links with one key: INVALID.
  static func linkKeyShared(
    _ key: String,
    first: ResolvedLink,
    count: Int,
  ) -> Diagnostic {
    located(
      first.path,
      line: first.startLine,
      code: .linkKeyShared,
      severity: .error,
      message: "\(count) regions share the link key '\(key)'; a key names one region, "
        + "so one binding cannot start twice on one line",
    )
  }

  /// Two links of one use case and role over some of the same bytes: a warning.
  static func overlappingLinks(
    _ first: ResolvedLink,
    _ second: ResolvedLink,
  ) -> Diagnostic {
    located(
      first.path,
      line: first.startLine,
      code: .overlappingLinks,
      severity: .warning,
      message: "redundant overlapping links: '\(first.key)' and '\(second.key)' cover some of "
        + "the same bytes",
    )
  }
}
