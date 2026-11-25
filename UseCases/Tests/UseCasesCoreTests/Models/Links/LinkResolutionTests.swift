import Testing
@testable import UseCasesCore

struct LinkResolutionTests {
  private func diagnostic(
    _ file: String,
    line: Int?,
    code: String,
    severity: DiagnosticSeverity,
  ) throws -> Diagnostic {
    try Diagnostic(
      file: WorkspacePath(validating: file),
      position: line.map { line in
        try SourcePosition(line: line)
      },
      code: DiagnosticCode(code),
      severity: severity,
      message: code,
    )
  }

  @Test
  func `problems and warnings are told apart and each is in report order`() throws {
    let diagnostics = try [
      diagnostic("src/b.swift", line: 3, code: "warn-b", severity: .warning),
      diagnostic("src/a.swift", line: 10, code: "error-a10", severity: .error),
      diagnostic("src/a.swift", line: 9, code: "error-a9", severity: .error),
      diagnostic("src/a.swift", line: 2, code: "warn-a", severity: .warning),
    ]

    let resolution = LinkResolution(
      links: [],
      diagnostics: diagnostics,
    )

    #expect(resolution.isInvalid)
    #expect(resolution.problems == ["src/a.swift:9: error-a9", "src/a.swift:10: error-a10"])
    #expect(resolution.warningLines == ["src/a.swift:2: warn-a", "src/b.swift:3: warn-b"])
  }

  @Test
  func `the warnings of the root files join the others in one report order`() throws {
    let fixture = try WorkspaceFixture()
    try fixture.write("use-cases-bridge.yml", "schema_version: 1\nvalidations: []\n")
    let workspace = try fixture.loaded()
    let resolution = try LinkResolution(
      links: [],
      diagnostics: [diagnostic("src/a.swift", line: 2, code: "warn-a", severity: .warning)],
    )

    #expect(resolution.warningLines == ["src/a.swift:2: warn-a"])
    #expect(resolution.warningLines(including: workspace) == [
      "src/a.swift:2: warn-a",
      "use-cases-bridge.yml: validations is empty: nothing is set up to verify",
    ])
  }

  @Test
  func `a resolution with a problem holds no links`() throws {
    let resolution = try LinkResolution(
      links: [ResolvedLink.sample()],
      diagnostics: [diagnostic("a", line: nil, code: "bad", severity: .error)],
    )

    #expect(resolution.links.isEmpty)
  }

  @Test
  func `a resolution with only warnings keeps its links, in the order of the links document`()
    throws
  {
    let resolution = try LinkResolution(
      links: [
        ResolvedLink.sample(binding: "b"),
        ResolvedLink.sample(binding: "a"),
      ],
      diagnostics: [diagnostic("a", line: nil, code: "note", severity: .warning)],
    )

    #expect(!resolution.isInvalid)
    #expect(resolution.links.map(\.binding) == ["a", "b"])
    #expect(resolution.problems.isEmpty)
  }

  @Test
  func `the same diagnostic found twice is reported once`() throws {
    let note = try diagnostic("a", line: 1, code: "note", severity: .warning)

    let resolution = LinkResolution(
      links: [],
      diagnostics: [note, note],
    )

    #expect(resolution.warningLines.count == 1)
  }
}
