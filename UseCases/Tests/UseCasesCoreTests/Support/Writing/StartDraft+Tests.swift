@testable import UseCasesCore

extension StartDraft {
  /// A draft that selects `auth-tests`, as `verify --start` would write it.
  static func sample(
    openedBy: RunOpener = .start,
    selected: [String] = ["auth-tests"],
  ) throws -> StartDraft {
    try StartDraft(
      openedBy: openedBy,
      selected: selected.map(IdentifierSegment.init(validating:)),
      validationsDigest: StoreSamples.digest("9"),
      routes: [
        StartedRoute(
          useCase: .sample(StoreSamples.useCase),
          route: .sample(StoreSamples.route),
          fingerprint: .sample("a"),
        ),
      ],
      files: [
        FileDigest(
          path: "Tests/AuthTests/LoginTests.swift",
          digest: StoreSamples.digest("f"),
        ),
      ],
      sources: selected.map { id in
        try RunSource(
          identifier: IdentifierSegment(validating: id),
          report: "reports/\(id)/\(id).jsonl",
          transformer: "swift-testing",
          workingDirectory: nil,
          command: nil,
          exitCode: nil,
          seconds: nil,
          error: nil,
          diagnostics: [],
        )
      },
    )
  }
}
