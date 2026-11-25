@testable import UseCasesCore

extension ResolvedLink {
  /// A link built from text, for tests that need no file.
  static func sample(
    source: LinkSource = .manual,
    useCase: String = "app.toggle",
    route: String? = nil,
    binding: String = "code",
    file: String = "src/a.swift",
    lines: ClosedRange<Int> = 1 ... 1,
    span: Range<Int>? = nil,
  ) throws -> ResolvedLink {
    let identity = try LinkIdentity(
      useCase: UseCaseIdentifier(validating: useCase),
      route: route.map { text in
        try RouteIdentifier(validating: text)
      },
      binding: BindingIdentifier(validating: binding),
    )

    return try ResolvedLink(
      source: source,
      identity: identity,
      path: WorkspacePath(validating: file),
      lines: lines,
      span: span ?? 0 ..< 10,
      contentRanges: [],
    )
  }
}
