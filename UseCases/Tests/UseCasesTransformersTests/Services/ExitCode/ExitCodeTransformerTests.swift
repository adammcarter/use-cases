import Testing
@testable import UseCasesTransformers

struct ExitCodeTransformerTests {
  private func respond(
    exitCode: Int?,
    links: [RequestLink],
    file: String? = "scripts/check.sh",
  ) throws -> ResultsResponse {
    let workspace = try ResultsWorkspace()
    var settings: [String: JSONValue] = [:]

    if let file {
      settings["file"] = .string(file)
    }

    return try ExitCodeTransformer().results(
      for: workspace.request(
        links: links,
        settings: settings,
        exitCode: exitCode,
      ),
    )
  }

  @Test(arguments: [(0, ResultStatus.pass), (1, .fail), (2, .fail), (127, .fail), (-1, .fail)])
  func `exit code 0 passes and anything else fails`(
    exitCode: Int,
    expected: ResultStatus,
  ) throws {
    let link = RequestLink.wholeFile("scripts/check.sh")

    let response = try respond(
      exitCode: exitCode,
      links: [link],
    )

    #expect(response.status(of: link) == expected)
    #expect(response.results.first?.message == "exit code \(exitCode)")
  }

  @Test
  func `every validation link in the file gets the same result, in request order`() throws {
    let second = RequestLink.validation(
      "scripts/check.sh",
      1,
      3,
      binding: "second",
    )
    let first = RequestLink.validation(
      "scripts/check.sh",
      4,
      9,
      binding: "first",
    )

    let response = try respond(
      exitCode: 1,
      links: [
        second,
        RequestLink.validation(
          "scripts/other.sh",
          1,
          9,
          binding: "elsewhere",
        ),
        RequestLink.implementation(
          "scripts/check.sh",
          1,
          9,
        ),
        first,
      ],
    )

    #expect(response.results.map(\.link) == [second.key, first.key])
    #expect(response.results.allSatisfy { $0.status == .fail })
  }

  @Test
  func `results carry a message and no test names, and nothing is unlinked`() throws {
    let response = try respond(
      exitCode: 0,
      links: [.wholeFile("scripts/check.sh")],
    )

    #expect(response.results.first?.tests == nil)
    #expect(response.unlinked.isEmpty)
  }

  @Test
  func `without an exit code there is no result, only a note`() throws {
    let response = try respond(
      exitCode: nil,
      links: [.wholeFile("scripts/check.sh")],
    )

    #expect(response.results.isEmpty)
    #expect(response
      .diagnostics == ["no exit code: exit-code works only with `use-cases verify --run`"])
  }

  @Test
  func `a file that no link is in gives no results`() throws {
    let response = try respond(
      exitCode: 1,
      links: [.wholeFile("scripts/other.sh")],
    )

    #expect(response.results.isEmpty)
  }

  @Test
  func `the file setting is required`() {
    #expect(throws: TransformerFailure.settingMissing("file")) {
      try respond(
        exitCode: 0,
        links: [],
        file: nil,
      )
    }
  }
}
