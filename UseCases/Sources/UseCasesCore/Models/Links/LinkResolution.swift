/// What link resolution found in a loaded workspace.
///
/// The links are only meaningful for a workspace that is not INVALID (chapter 09 §26), so a
/// resolution with any problem holds no links.
public struct LinkResolution: Equatable, Sendable {
  /// Every link in the order of chapter 16 §13: use case id, then route (implementation links
  /// first), then binding id, then file, then start line as a number. Empty when
  /// ``isInvalid``.
  public let links: [ResolvedLink]

  /// Every problem that makes the workspace INVALID, in report order (chapter 09 §27.1).
  let errors: [Diagnostic]

  /// Everything worth saying that does not: the load's own warnings and the link warnings,
  /// together, in report order.
  let warnings: [Diagnostic]

  /// Whether a problem makes the workspace INVALID.
  public var isInvalid: Bool {
    !errors.isEmpty
  }

  /// Each problem on a line, `<file>:<line>: <message>` or `<file>: <message>`, in report order.
  public var problems: [String] {
    errors.map(\.description)
  }

  /// Each warning on a line in the same form, in report order.
  public var warningLines: [String] {
    warnings.map(\.description)
  }

  /// The warnings of the links and of the load, with those of the optional root files, the
  /// bridge settings and the groups, in one report order. They are only said where a command
  /// reports the whole workspace: `validate` and `status` (chapter 16 §8).
  public func warningLines(including workspace: LoadedWorkspace) -> [String] {
    (warnings + workspace.rootFileWarnings).inReportOrder.map(\.description)
  }

  /// Splits `diagnostics` into the problems and the warnings, each in report order.
  init(
    links: [ResolvedLink],
    diagnostics: [Diagnostic],
  ) {
    let ordered = diagnostics.inReportOrder
    let errors = ordered.filter { diagnostic in
      diagnostic.severity == .error
    }

    self.errors = errors
    warnings = ordered.filter { diagnostic in
      diagnostic.severity == .warning
    }
    self.links = errors.isEmpty ? links.inLinkOrder : []
  }
}
