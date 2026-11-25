import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

/// A signal that comes after the reports were read and the code was looked at again (chapter 13
/// §15, "cancelled after judging").
struct VerifyFinisherSealCancellationTests {
  private let fixture: VerifyFixture

  init() throws {
    fixture = try VerifyFixture()
  }

  private func finish(raisingAtTheGuard raises: Bool) async throws -> VerifiedRun {
    let started = try fixture.start()
    try fixture.writeReport(of: started)

    let cancellation = CancellationSwitch()
    let key = try fixture.linkKey()
    let runner = try MockTransformerRunner(
      answers: [.success(VerifyFixture.response([key: "pass"]))],
    )

    return try await fixture.finisher(
      runner: runner,
      cancellation: cancellation,
    ).finish(
      VerifyFinishRequest(runIdentifier: nil),
      in: fixture.resolved(),
      reloading: FixtureReloading(fixture) {
        if raises {
          cancellation.raise()
        }
      },
    )
  }

  @Test
  func `a signal after the last check but before the seal seals the run as interrupted`()
    async throws
  {
    let verified = try await finish(raisingAtTheGuard: true)
    let run = try #require(try fixture.history().runs.first)

    #expect(verified.isCancelled)
    #expect(run.termination == .interrupted)
  }

  @Test
  func `the verdicts already appended are kept, since judging was done`() async throws {
    let verified = try await finish(raisingAtTheGuard: true)
    let run = try #require(try fixture.history().runs.first)

    #expect(verified.verdictCounts.map(\.status) == ["pass"])
    #expect(run.results.map(\.verdict) == [.pass])
    #expect(verified.notes == [FinishPoint.cancelledAfterJudging])
  }

  @Test
  func `without a signal the same run is completed`() async throws {
    let verified = try await finish(raisingAtTheGuard: false)

    #expect(!verified.isCancelled)
    #expect(try fixture.history().runs.first?.termination == .completed)
  }
}
