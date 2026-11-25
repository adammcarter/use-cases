import Foundation
import Testing
@testable import UseCasesCore

/// What the tests wrote into `reports/` is never followed and never makes a run unsealable
/// (chapter 12 §15): an entry that is not a regular file is a run error that names it.
struct VerifyReportEntriesTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func link(
    _ name: String,
    in folder: String,
    to target: String,
  ) throws {
    try FileManager.default.createDirectory(
      atPath: folder,
      withIntermediateDirectories: true,
    )
    try FileManager.default.createSymbolicLink(
      atPath: folder + "/" + name,
      withDestinationPath: target,
    )
  }

  private func finish(started: StartedVerifyRun) async throws -> VerifiedRun {
    let runner = try MockTransformerRunner(
      answers: [.success(VerifyFixture.response([fixture.linkKey(): "pass"]))],
    )

    return try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )
  }

  private func reportsFolder(of started: StartedVerifyRun) throws -> String {
    let run = try #require(started.runIdentifier)

    return fixture.runFolder(run).path + "/reports"
  }

  // Mutant: RunWriter+Sealing digests `reports/` with `access.bytes` and throws on a name that is
  // not a regular file (the old `digests(of:)`), after `finalize` has replaced run.json. The seal
  // then fails with "corrupt" and the finish throws.

  @Test
  func `a symlink in a validation's folder gives a run error that names it, and the run seals`()
    async throws
  {
    let started = try fixture.start()
    let folder = try reportsFolder(of: started) + "/unit-tests"

    try fixture.writeReport(of: started)
    try link("latest", in: folder, to: "unit.xml")

    let verified = try await finish(started: started)

    #expect(
      verified.errors == [
        "unit-tests: reports/unit-tests/latest is not a regular file "
          + "(a symlink or a special file); it is never followed",
      ],
    )
    #expect(verified.results.isEmpty)
    #expect(try fixture.history().runs.count == 1)
    #expect(try fixture.history().unfinishedRuns.isEmpty)
  }

  @Test
  func `the transformer is never asked for a report with a symlink in it`() async throws {
    let started = try fixture.start()

    try fixture.writeReport(of: started)
    try link("latest", in: reportsFolder(of: started) + "/unit-tests", to: "/etc")

    let runner = MockTransformerRunner(answers: [])
    let verified = try await fixture.finisher(runner: runner).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture),
    )

    #expect(verified.hasRunErrors)
    #expect(await runner.calls.isEmpty)
  }

  @Test
  func `a symlink outside every validation's folder is a run error too, and the run seals`()
    async throws
  {
    let started = try fixture.start()

    try fixture.writeReport(of: started)
    try link("link", in: reportsFolder(of: started) + "/stray", to: "/etc")

    let verified = try await finish(started: started)

    #expect(
      verified.errors == [
        "stray: reports/stray/link is not a regular file "
          + "(a symlink or a special file); it is never followed",
      ],
    )
    #expect(verified.results.count == 1)
    #expect(try fixture.history().runs.count == 1)
  }

  @Test
  func `a symlink to a folder is not followed into it`() async throws {
    let started = try fixture.start()

    try fixture.writeReport(of: started)
    try link("folder", in: reportsFolder(of: started) + "/stray", to: NSTemporaryDirectory())

    let verified = try await finish(started: started)

    #expect(verified.errors.count == 1)
    #expect(try fixture.history().runs.count == 1)
  }

  @Test
  func `a symlink is not a finding on the sealed run either: it was named, once`() async throws {
    let started = try fixture.start()

    try fixture.writeReport(of: started)
    try link("link", in: reportsFolder(of: started) + "/stray", to: "/etc")
    _ = try await finish(started: started)

    #expect(try fixture.history().findings.isEmpty)
  }

  @Test
  func `an abort seals a run with a symlink in its reports`() async throws {
    let started = try fixture.start()

    try link("link", in: reportsFolder(of: started) + "/unit-tests", to: "/etc")
    _ = try await fixture.aborter().abort(
      VerifyAbortRequest(runIdentifier: nil),
      in: fixture.workspace,
    )

    #expect(try fixture.history().runs.first?.termination == .interrupted)
  }

  @Test(.enabled(if: getuid() != 0, "root can read every file"))
  func `a file the core cannot read is a run error, not a refusal to seal`() async throws {
    let started = try fixture.start()

    try fixture.writeReport(of: started)
    let path = try #require(started.reports.first).path

    try FileManager.default.setAttributes(
      [.posixPermissions: 0],
      ofItemAtPath: path,
    )
    defer {
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o644],
        ofItemAtPath: path,
      )
    }

    let verified = try await finish(started: started)

    #expect(verified.hasRunErrors)
    #expect(verified.errors.first?.contains("cannot be read") == true)
    #expect(try fixture.history().runs.count == 1)
  }

  @Test
  func `an ordinary report digests as before`() async throws {
    let started = try fixture.start()

    try fixture.writeReport(of: started)

    let verified = try await finish(started: started)

    #expect(verified.errors.isEmpty)
    #expect(verified.results.count == 1)
  }
}
