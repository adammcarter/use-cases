import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterReadReportsTests {
  private let fixture: WriterFixture

  init() throws {
    fixture = try WriterFixture()
  }

  private func openRun() throws -> OpenRun {
    let run = try fixture.writer.openVerifyRun(
      StartDraft.sample(),
      in: fixture.workspace,
    )

    try fixture.directory.write(
      ".use-cases/runs/\(run.identifier.text)/reports/auth-tests/a.jsonl",
      "as it is now",
    )

    return run
  }

  private func sealed(_ run: OpenRun) throws -> [FileDigest] {
    try #require(
      try fixture.readHistory().runs.first { $0.identifier == run.identifier }?
        .completion.details?.reportDigests,
    )
  }

  @Test
  func `a report nobody read is digested as it is at the seal`() throws {
    let run = try openRun()

    _ = try fixture.writer.seal(
      run,
      termination: .completed,
    )

    #expect(
      try sealed(run) == [
        FileDigest(
          path: "auth-tests/a.jsonl",
          digest: SHA256Hasher().sha256Hex(of: Array("as it is now".utf8)),
        ),
      ],
    )
  }

  @Test
  func `a report that was read is sealed as it was read, not as it is`() throws {
    let run = try openRun()
    let read = FileDigest(
      path: "auth-tests/a.jsonl",
      digest: StoreSamples.digest("1"),
    )

    _ = try fixture.writer.seal(
      run,
      termination: .completed,
      readReports: [read],
    )

    #expect(try sealed(run) == [read])
    #expect(try fixture.readHistory().findings.map(\.description).count == 1)
  }

  @Test
  func `files only the reader saw and files only the seal sees are both sealed, sorted`() throws {
    let run = try openRun()
    let gone = FileDigest(
      path: "auth-tests/0-gone.jsonl",
      digest: StoreSamples.digest("2"),
    )

    _ = try fixture.writer.seal(
      run,
      termination: .completed,
      readReports: [gone],
    )

    #expect(try sealed(run).map(\.path) == ["auth-tests/0-gone.jsonl", "auth-tests/a.jsonl"])
  }
}
