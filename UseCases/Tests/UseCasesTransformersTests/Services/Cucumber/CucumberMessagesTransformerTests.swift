import Testing
@testable import UseCasesTransformers

struct CucumberMessagesTransformerTests {
  private typealias Stream = CucumberStream

  private func respond(
    to lines: [String],
    links: [RequestLink],
    settings: [String: JSONValue] = [:],
    workingDirectory: String = ".",
  ) throws -> ResultsResponse {
    let workspace = try ResultsWorkspace()

    try workspace.writeReport(Stream.stream(lines))

    return try CucumberMessagesTransformer().results(
      for: workspace.request(
        links: links,
        settings: settings,
        workingDirectory: workingDirectory,
      ),
    )
  }

  @Test
  func `an outline's example rows merge into its link, worst first`() throws {
    let outline = RequestLink.validation(
      "features/returns.feature",
      1,
      12,
    )
    let lines = Stream.scenario(
      "row 1",
      uri: "features/returns.feature",
      line: 9,
      steps: ["PASSED"],
    )
      + Stream.scenario(
        "row 2",
        uri: "features/returns.feature",
        line: 10,
        steps: ["PASSED", "FAILED"],
      )

    let response = try respond(
      to: lines,
      links: [outline],
    )

    #expect(response.status(of: outline) == .fail)
    #expect(
      response.results.first?.tests == [
        "features/returns.feature:10 row 2",
        "features/returns.feature:9 row 1",
      ],
    )
  }

  @Test
  func `a pending scenario is incomplete and an ambiguous one an error`() throws {
    let pending = RequestLink.validation(
      "features/a.feature",
      1,
      4,
      binding: "pending",
    )
    let ambiguous = RequestLink.validation(
      "features/a.feature",
      5,
      8,
      binding: "ambiguous",
    )
    let lines = Stream.scenario(
      "p",
      line: 2,
      steps: ["PASSED", "PENDING"],
    )
      + Stream.scenario(
        "a",
        line: 6,
        steps: ["AMBIGUOUS"],
      )

    let response = try respond(
      to: lines,
      links: [pending, ambiguous],
    )

    #expect(response.status(of: pending) == .incomplete)
    #expect(response.status(of: ambiguous) == .error)
  }

  @Test
  func `a scenario outside every link is unlinked`() throws {
    let response = try respond(
      to: Stream.scenario(
        "free",
        line: 20,
        steps: ["PASSED"],
      ),
      links: [.validation(
        "features/a.feature",
        1,
        4,
      )],
    )

    #expect(
      response.unlinked == [
        UnlinkedTest(
          test: "features/a.feature:20 free",
          file: "features/a.feature",
          line: 20,
          status: .pass,
        ),
      ],
    )
  }

  @Test
  func `feature paths start at the working folder, or at the base setting`() throws {
    let link = RequestLink.validation(
      "bdd/features/a.feature",
      1,
      4,
    )
    let lines = Stream.scenario(
      "s",
      line: 2,
      steps: ["PASSED"],
    )

    let fromWorkingFolder = try respond(
      to: lines,
      links: [link],
      workingDirectory: "bdd",
    )
    let fromBase = try respond(
      to: lines,
      links: [link],
      settings: ["base": .string("bdd")],
    )
    let fromRoot = try respond(
      to: lines,
      links: [link],
    )

    #expect(fromWorkingFolder.status(of: link) == .pass)
    #expect(fromBase.status(of: link) == .pass)
    #expect(fromRoot.status(of: link) == nil)
  }

  @Test
  func `notes about lines that are not messages are passed on`() throws {
    let response = try respond(
      to: ["oops"] + Stream.scenario(
        "s",
        line: 2,
        steps: ["PASSED"],
      ),
      links: [],
    )

    #expect(response.diagnostics == ["line 1 is not a message; ignored"])
  }

  @Test
  func `no report is a failure that names it`() throws {
    let workspace = try ResultsWorkspace()

    #expect(throws: TransformerFailure.self) {
      try CucumberMessagesTransformer().results(for: workspace.request(links: []))
    }
  }

  @Test(arguments: ["\u{2028}", "\u{2029}", "\u{85}", "\r", "\u{B}"])
  func `a failed step whose message holds a line separator still fails the scenario`(
    separator: String,
  ) throws {
    let link = RequestLink.validation(
      "features/a.feature",
      1,
      9,
    )
    let lines = [
      Stream.pickle(
        "p",
        uri: "features/a.feature",
        name: "n",
        line: 3,
      ),
      Stream.testCase(
        "c",
        pickle: "p",
      ),
      Stream.started(
        "s",
        testCase: "c",
      ),
      Stream.step(
        "PASSED",
        start: "s",
      ),
      Stream.step(
        "FAILED",
        start: "s",
        message: "expected 1\(separator)got 2",
      ),
    ]

    let response = try respond(
      to: lines,
      links: [link],
    )

    #expect(response.status(of: link) == .fail)
    #expect(response.diagnostics.isEmpty)
  }
}
