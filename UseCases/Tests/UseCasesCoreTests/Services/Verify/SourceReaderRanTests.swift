import Foundation
import Testing
@testable import UseCasesCore

/// What `verify --run` tells the reader about the command it ran (chapter 13 §7 step 3).
struct SourceReaderRanTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func read(
    ran: RanCommand?,
    answer: [String: String],
    writingReport: Bool = true,
  ) async throws -> SourceOutcome {
    let started = try fixture.start()

    if writingReport {
      try fixture.writeReport(of: started)
    }

    let resolved = try fixture.resolved()
    let validation = try #require(resolved.workspace.bridge?.validations.first)
    let run = try fixture.store.writer.reopenRun(
      RunIdentifier(validating: #require(started.runIdentifier)),
      in: fixture.workspace,
    )
    let runner = try MockTransformerRunner(answers: [.success(VerifyFixture.response(answer))])

    return await SourceReader(access: fixture.store.access).read(
      validation,
      run: run,
      in: resolved,
      ran: ran,
      using: runner,
    )
  }

  private func command(
    exitCode: Int32? = 0,
    failure: String? = nil,
  ) -> RanCommand {
    RanCommand(
      command: ["swift", "test"],
      failure: failure,
      exitCode: exitCode,
      seconds: 1.5,
    )
  }

  @Test
  func `the source says which command ran, how it ended and for how long`() async throws {
    let key = try fixture.linkKey()

    let outcome = try await read(
      ran: command(),
      answer: [key: "pass"],
    )

    #expect(outcome.source.command == ["swift", "test"])
    #expect(outcome.source.exitCode == 0)
    #expect(outcome.source.seconds == 1.5)
    #expect(outcome.source.error == nil)
    #expect(outcome.results.map(\.status) == [.pass])
  }

  @Test
  func `a command that could not run is the run error, and nothing is read`() async throws {
    let outcome = try await read(
      ran: command(exitCode: nil, failure: "command timed out after 1 seconds"),
      answer: [:],
    )

    #expect(outcome.source.error == "command timed out after 1 seconds")
    #expect(outcome.results.isEmpty)
    #expect(outcome.runError == "unit-tests: command timed out after 1 seconds")
  }

  @Test
  func `a non-zero exit with no failing test is a build failure: no results from the source`()
    async throws
  {
    let key = try fixture.linkKey()

    let outcome = try await read(
      ran: command(exitCode: 2),
      answer: [key: "pass"],
    )

    #expect(
      outcome.source.error == "command exited 2 without any failing test (build failure?)",
    )
    #expect(outcome.results.isEmpty)
  }

  @Test(arguments: ["fail", "error"])
  func `a non-zero exit with a failing test is a failure of the tests, not of the build`(
    status: String,
  ) async throws {
    let key = try fixture.linkKey()

    let outcome = try await read(
      ran: command(exitCode: 1),
      answer: [key: status],
    )

    #expect(outcome.source.error == nil)
    #expect(outcome.results.count == 1)
  }

  @Test
  func `a command that wrote no report says {report}, not the path --start gave`() async throws {
    let outcome = try await read(
      ran: command(),
      answer: [:],
      writingReport: false,
    )

    #expect(outcome.source.error?.hasSuffix("({report})") == true)
  }
}
