import Testing
@testable import UseCasesCore

struct RunManifestDocumentTests {
  private func manifest(
    kind: RunKind = .record,
    sources: [RunSource] = [],
  ) throws -> RunManifest {
    try RunManifest(
      identifier: .sample(42),
      createdAt: StoreSamples.timestamp,
      kind: kind,
      sources: sources,
      errors: ["a report was missing"],
      diagnostics: [
        RunDiagnostic(
          problem: "code changed during the run",
          useCase: .sample("shop.login.remember-me"),
          route: .sample("unit-tests"),
          fingerprint: .sample("a"),
          files: [WorkspacePath(validating: "Sources/Auth/LoginService.swift")],
          links: [StoreSamples.linkKey],
        ),
        RunDiagnostic(
          problem: "marker for an unknown use case",
          useCase: nil,
          route: nil,
          fingerprint: nil,
          files: [],
          links: [],
        ),
      ],
      unlinkedTests: [
        UnlinkedTest(
          test: "AuthTests/notTied()",
          file: "Tests/AuthTests/LoginTests.swift",
          line: 35,
          status: .pass,
        ),
        UnlinkedTest(
          test: "AuthTests/anonymous()",
          file: nil,
          line: nil,
          status: .incomplete,
        ),
      ],
      notes: ["aborted: closed by `use-cases verify --abort`"],
    )
  }

  private func source() throws -> RunSource {
    try RunSource(
      identifier: IdentifierSegment(validating: "auth-tests"),
      report: "reports/auth-tests/auth-tests.jsonl",
      transformer: "swift-testing",
      workingDirectory: WorkspacePath(validating: "Packages/Auth"),
      command: ["swift", "test", "--filter", "AuthTests"],
      exitCode: 1,
      seconds: 1.7,
      error: nil,
      diagnostics: ["2 tests had no source line"],
    )
  }

  @Test
  func `a record manifest passes the run schema`() throws {
    let document = try WrittenDocument(
      manifest().document,
      schema: .run,
    )

    #expect(document.failures.isEmpty)
  }

  @Test
  func `a manifest with a source that ran its command passes the run schema`() throws {
    let document = try WrittenDocument(
      manifest(
        kind: .verify,
        sources: [source()],
      ).document,
      schema: .run,
    )

    #expect(document.failures.isEmpty)
  }

  @Test
  func `the reader reads back exactly the manifest that was written`() throws {
    let written = try manifest(
      kind: .verify,
      sources: [source()],
    )
    let document = try WrittenDocument(
      written.document,
      schema: .run,
    )

    #expect(try RunManifest(authored: document.object) == written)
  }

  @Test
  func `a field a source does not have is left out`() throws {
    let bare = try RunSource(
      identifier: IdentifierSegment(validating: "auth-tests"),
      report: "reports/auth-tests",
      transformer: "swift-testing",
      workingDirectory: nil,
      command: nil,
      exitCode: nil,
      seconds: nil,
      error: "report changed while it was read",
      diagnostics: [],
    )
    let document = try WrittenDocument(
      manifest(sources: []).document,
      schema: .run,
    )
    let written = bare.document

    #expect(document.failures.isEmpty)
    #expect(
      written == .members([
        "id": .string("auth-tests"),
        "report": .string("reports/auth-tests"),
        "transformer": .string("swift-testing"),
        "error": .string("report changed while it was read"),
      ]),
    )
  }
}
