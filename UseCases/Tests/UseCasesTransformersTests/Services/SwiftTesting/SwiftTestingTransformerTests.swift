import Testing
@testable import UseCasesTransformers

struct SwiftTestingTransformerTests {
  private typealias Stream = SwiftTestingStream

  private func authStream(file: String) -> String {
    Stream.stream(
      Stream.test(
        "A.one()",
        file: file,
        line: 4,
      ),
      Stream.test(
        "A.two()",
        file: file,
        line: 12,
      ),
      Stream.test(
        "A.three()",
        file: file,
        line: 20,
      ),
      Stream.ended("A.one()"),
      Stream.issue(
        "A.two()",
        isKnown: false,
      ),
      Stream.ended("A.two()"),
      Stream.ended("A.three()"),
    )
  }

  @Test
  func `each link gets the worst of the tests inside its lines`() throws {
    let workspace = try ResultsWorkspace()
    let file = workspace.folder.absolute("Tests/AuthTests.swift")
    let passing = RequestLink.validation(
      "Tests/AuthTests.swift",
      1,
      10,
      binding: "ok",
    )
    let failing = RequestLink.validation(
      "Tests/AuthTests.swift",
      11,
      30,
      binding: "bad",
    )

    try workspace.writeReport(authStream(file: file))

    let response = try SwiftTestingTransformer().results(
      for: workspace.request(links: [passing, failing]),
    )

    #expect(response.status(of: passing) == .pass)
    #expect(response.status(of: failing) == .fail)
    #expect(
      response.results.first { result in
        result.link == failing.key
      }?.tests == ["A.three()", "A.two()"],
    )
    #expect(response.unlinked.isEmpty)
    #expect(response.diagnostics.isEmpty)
  }

  @Test
  func `a test inside no link is reported as unlinked`() throws {
    let workspace = try ResultsWorkspace()
    let file = workspace.folder.absolute("Tests/AuthTests.swift")

    try workspace.writeReport(
      Stream.stream(
        Stream.test(
          "A.free()",
          file: file,
          line: 35,
        ),
        Stream.ended("A.free()"),
      ),
    )

    let response = try SwiftTestingTransformer().results(
      for: workspace.request(links: [.validation(
        "Tests/AuthTests.swift",
        1,
        10,
      )]),
    )

    #expect(response.results.isEmpty)
    #expect(
      response.unlinked == [
        UnlinkedTest(
          test: "A.free()",
          file: "Tests/AuthTests.swift",
          line: 35,
          status: .pass,
        ),
      ],
    )
  }

  @Test
  func `a known issue and a skip are incomplete`() throws {
    let workspace = try ResultsWorkspace()
    let file = workspace.folder.absolute("Tests/a.swift")
    let known = RequestLink.validation(
      "Tests/a.swift",
      1,
      5,
      binding: "known",
    )
    let skipped = RequestLink.validation(
      "Tests/a.swift",
      6,
      9,
      binding: "skipped",
    )

    try workspace.writeReport(
      Stream.stream(
        Stream.test(
          "A.known()",
          file: file,
          line: 2,
        ),
        Stream.test(
          "A.skipped()",
          file: file,
          line: 7,
        ),
        Stream.issue(
          "A.known()",
          isKnown: true,
        ),
        Stream.ended("A.known()"),
        Stream.skipped("A.skipped()"),
      ),
    )

    let response = try SwiftTestingTransformer().results(
      for: workspace.request(links: [known, skipped]),
    )

    #expect(response.status(of: known) == .incomplete)
    #expect(response.status(of: skipped) == .incomplete)
  }

  @Test
  func `a saved stream gives the same answer when the code root does not exist`() throws {
    let workspace = try ResultsWorkspace()
    let request = ResultsRequest(
      links: [.validation(
        "Tests/a.swift",
        1,
        9,
      )],
      output: ReportOutput(
        reportPath: workspace.reportPath,
        exitCode: 1,
      ),
      codeRoot: "/FROZEN",
    )

    try workspace.writeReport(
      Stream.stream(
        Stream.test(
          "A.t()",
          file: "/FROZEN/Tests/a.swift",
          line: 4,
        ),
        Stream.ended("A.t()"),
      ),
    )

    let response = try SwiftTestingTransformer().results(for: request)

    #expect(response.results.map(\.status) == [.pass])
  }

  @Test
  func `no report says so and gives no results`() throws {
    let workspace = try ResultsWorkspace()

    let response = try SwiftTestingTransformer().results(
      for: workspace.request(links: [.validation(
        "Tests/a.swift",
        1,
        9,
      )]),
    )

    #expect(response.results.isEmpty)
    #expect(response.diagnostics == ["no report was written, so no test results are available"])
  }

  @Test
  func `issues outside any test are noted`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.writeReport(Stream.stream(Stream.issue(
      nil,
      isKnown: false,
    )))

    let response = try SwiftTestingTransformer().results(for: workspace.request(links: []))

    #expect(response.diagnostics == ["1 issue(s) recorded outside any test"])
  }

  @Test
  func `a damaged stream is a failure, never a partial answer`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.writeReport("{\"kind\": \"test\"}\ngarbage\n")

    #expect(throws: TransformerFailure.self) {
      try SwiftTestingTransformer().results(for: workspace.request(links: []))
    }
  }

  @Test
  func `a report that is a folder cannot be read as a stream`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.writeReportFile(
      "events.jsonl",
      "",
    )

    #expect(throws: TransformerFailure.self) {
      try SwiftTestingTransformer().results(for: workspace.request(links: []))
    }
  }

  @Test
  func `the report is read through the reader it is given`() throws {
    let stream = Stream.stream(
      Stream.test(
        "A.t()",
        file: "/w/Tests/a.swift",
        line: 2,
      ),
      Stream.ended("A.t()"),
    )
    let link = RequestLink.validation(
      "Tests/a.swift",
      1,
      5,
    )
    let request = ResultsRequest(
      links: [link],
      output: ReportOutput(
        reportPath: "/memory/events.jsonl",
        exitCode: nil,
      ),
      codeRoot: "/w",
    )

    let response = try SwiftTestingTransformer(
      reader: MockReportReader(texts: ["/memory/events.jsonl": stream]),
    ).results(for: request)

    #expect(response.status(of: link) == .pass)
  }
}
