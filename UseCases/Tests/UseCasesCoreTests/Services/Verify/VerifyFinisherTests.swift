import Foundation
import Testing
@testable import UseCasesCore

struct VerifyFinisherTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  /// Starts a run, has the tests write their report, and finishes it with a transformer that
  /// answers `statuses`.
  private func finished(
    _ statuses: [String: String]? = nil,
    diagnostics: [String] = [],
  ) async throws -> (started: StartedVerifyRun, verified: VerifiedRun) {
    let started = try fixture.start()

    try fixture.writeReport(of: started)

    let key = try fixture.linkKey()
    let runner = try MockTransformerRunner(
      answers: [.success(VerifyFixture.response(
        statuses ?? [key: "pass"],
        diagnostics: diagnostics,
      ))],
    )
    let verified = try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )

    return (started, verified)
  }

  @Test
  func `a link that passed gives its route a verdict, sealed in the run that was started`()
    async throws
  {
    let (started, verified) = try await finished()

    #expect(verified.runIdentifier == started.runIdentifier)
    #expect(verified.verdictCounts.map(\.status) == ["pass"])
    #expect(!verified.hasRunErrors)

    let history = try fixture.history()
    let run = try #require(history.runs.first)

    #expect(history.runs.count == 1)
    #expect(history.unfinishedRuns.isEmpty)
    #expect(run.termination == .completed)
    #expect(run.results.map(\.verdict) == [.pass])
    #expect(run.results.first?.route.text == "unit-tests")
  }

  @Test
  func `the verdict is fingerprinted at the start point and names the validations that spoke`()
    async throws
  {
    let (_, verified) = try await finished()

    let result = try #require(verified.results.first)
    let stamp = try fixture.read(
      ".use-cases/runs/\(#require(verified.runIdentifier))/start.json",
    )

    #expect(stamp.contains(result.fingerprint.text))
    guard case let .validations(via, links)? = result.detail?.origin else {
      Issue.record("not a verify result")
      return
    }

    #expect(via.map(\.text) == ["unit-tests"])
    #expect(links.map(\.verdict) == [.pass])
  }

  @Test
  func `a failing link fails its route`() async throws {
    let key = try fixture.linkKey()
    let (_, verified) = try await finished([key: "fail"])

    #expect(verified.verdictCounts.map(\.status) == ["fail"])
    #expect(!verified.hasRunErrors)
  }

  @Test
  func `a route whose link got no result has no verdict, and the run says which link`()
    async throws
  {
    let (_, verified) = try await finished([:])
    let key = try fixture.linkKey()
    let manifest = try #require(verified.manifest)
    let diagnostic = try #require(manifest.diagnostics.first { $0.route?.text == "unit-tests" })

    #expect(verified.results.isEmpty)
    #expect(diagnostic.problem == "its test didn't run")
    #expect(diagnostic.links == [key])
    #expect(diagnostic.fingerprint != nil)
  }

  @Test
  func `the sources of the manifest say which report was read, and what the transformer said`()
    async throws
  {
    let (_, verified) = try await finished(diagnostics: ["2 tests had no source line"])
    let source = try #require(verified.manifest?.sources.first)

    #expect(source.identifier.text == "unit-tests")
    #expect(source.report == "reports/unit-tests/unit.xml")
    #expect(source.transformer == "junit")
    #expect(source.command == nil)
    #expect(source.exitCode == nil)
    #expect(source.diagnostics == ["2 tests had no source line"])
  }

  @Test
  func `the report is sealed as it was read, beside the run's own files`() async throws {
    let (started, verified) = try await finished()
    let run = try #require(verified.runIdentifier)
    let sealed = try fixture.read(".use-cases/runs/\(run)/completion.json")
    let report = try #require(started.reports.first)

    #expect(sealed.contains("\"unit-tests/unit.xml\""))
    #expect(sealed.contains("\"start_sha256\""))
    #expect(FileManager.default.fileExists(atPath: report.path))
    #expect(try fixture.history().findings.isEmpty)
  }

  @Test
  func `the transformer is asked for the report in place, with no exit code`() async throws {
    let started = try fixture.start()
    try fixture.writeReport(of: started)
    let runner = try MockTransformerRunner(
      answers: [.success(VerifyFixture.response([:]))],
    )

    _ = try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )

    let call = try #require(await runner.calls.first)
    guard case let .object(members) = call.request,
          let output = members.first(where: { $0.key == "output" })?.value,
          case let .object(fields) = output
    else {
      Issue.record("no output in the request")
      return
    }

    let report = try #require(started.reports.first).path
    let exitCode = fields.first { field in
      field.key == "exit_code"
    }
    let workingDir = fields.first { field in
      field.key == "working_dir"
    }
    let reportPath = fields.first { field in
      field.key == "report_path"
    }

    #expect(call.job == .results)
    #expect(exitCode?.value == .null)
    #expect(workingDir?.value == .string("."))
    #expect(reportPath?.value == .string(report))
  }

  @Test
  func `with no bridge settings nothing is read and no run is written`() async throws {
    let bare = try VerifyFixture(bridge: nil)
    let runner = MockTransformerRunner(answers: [])

    let verified = try await bare.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: bare.resolved(),
      reloading: FixtureReloading(bare),
    )

    #expect(verified.runIdentifier == nil)
    #expect(verified.notes.first?.contains("use-cases record") == true)
    #expect(bare.runs().isEmpty)
    #expect(await runner.calls.isEmpty)
  }
}
