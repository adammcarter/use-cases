import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterSealingTests {
  private let fixture: WriterFixture
  private let hasher = SHA256Hasher()

  init() throws {
    fixture = try WriterFixture()
  }

  private func open(kind: RunKind = .record) throws -> OpenRun {
    try fixture.writer.openRun(
      kind: kind,
      in: fixture.workspace,
    )
  }

  private func folder(_ run: OpenRun) -> String {
    ".use-cases/runs/\(run.identifier.text)"
  }

  private func digest(_ path: String) throws -> String {
    try hasher.sha256Hex(of: Array(fixture.read(path).utf8))
  }

  @Test
  func `a sealed record run is read back with its verdict`() throws {
    let run = try fixture.recordRun([WriterFixture.result(.fail)])

    let history = try fixture.readHistory()

    let stored = try #require(history.runs.first)
    #expect(history.runs.count == 1)
    #expect(stored.identifier == run.identifier)
    #expect(stored.manifest == run.manifest)
    #expect(stored.termination == .completed)
    #expect(stored.findings.isEmpty)
    #expect(stored.results == [WriterFixture.result(.fail)])
  }

  @Test
  func `the latest result of a route is the one the reader finds`() throws {
    try fixture.recordRun([WriterFixture.result(.fail)])
    try fixture.recordRun([WriterFixture.result(.pass)])

    let history = try fixture.readHistory()
    let latest = history.latestResult(
      useCase: .sample(StoreSamples.useCase),
      route: .sample(StoreSamples.route),
      fingerprint: .sample("a"),
    )

    #expect(latest?.result.verdict == .pass)
  }

  @Test
  func `the log is one compact line with sorted keys and a line feed`() throws {
    let run = try fixture.recordRun([WriterFixture.result(.pass)])

    #expect(
      try fixture.read("\(folder(run))/results.jsonl") == """
      {"fingerprint":"\(RouteFingerprint.sample("a").text)","message":"checked by hand",\
      "record_version":1,"recorded_at":"\(StoreSamples.timestamp)","route":"\(StoreSamples.route)",\
      "status":"pass","use_case":"\(StoreSamples.useCase)","via":["record"]}

      """,
    )
  }

  @Test
  func `the marker is printed with a space after each colon, as the suite's tamper test needs`(
  ) throws {
    let run = try fixture.recordRun()
    let marker = try fixture.read("\(folder(run))/completion.json")

    #expect(marker.contains("\"result_count\": 1"))
    #expect(marker.contains("\"termination\": \"completed\""))
    #expect(marker.contains("\"outputs_sha256\": {}"))
    #expect(marker.contains("\"reports_sha256\": {}"))
    #expect(!marker.contains("start_sha256"))
  }

  @Test
  func `the marker's digests are those of the exact files`() throws {
    let run = try fixture.recordRun()
    let marker = try fixture.read("\(folder(run))/completion.json")
    let manifest = try digest("\(folder(run))/run.json")
    let results = try digest("\(folder(run))/results.jsonl")

    #expect(marker.contains("\"manifest_sha256\": \"\(manifest)\""))
    #expect(marker.contains("\"results_sha256\": \"\(results)\""))
  }

  @Test
  func `every file a record run is made of passes the bundled schema`() throws {
    let run = try fixture.recordRun()
    let checks = try StoreWriteChecks(loader: BundledStoreSchemaLoader())
    let reader = JSONReader()

    func value(_ path: String) throws -> AuthoredValue {
      try reader.read(fixture.read(path))
    }

    let log = try fixture.read("\(folder(run))/results.jsonl")
    let line = String(log.dropLast())

    #expect(try checks.run.check(value("\(folder(run))/run.json")).isEmpty)
    #expect(try checks.result.check(reader.read(line)).isEmpty)
    #expect(try checks.completion.check(value("\(folder(run))/completion.json")).isEmpty)
    #expect(try checks.runOrder.check(value(".use-cases/run-order.json")).isEmpty)
  }

  @Test
  func `a run with no results seals with a count of zero`() throws {
    let run = try fixture.recordRun([])

    let stored = try #require(fixture.readHistory().runs.first)

    #expect(stored.results.isEmpty)
    #expect(try fixture.read("\(folder(run))/completion.json").contains("\"result_count\": 0"))
  }

  @Test
  func `a run closed as interrupted says so`() throws {
    let run = try open()

    _ = try fixture.writer.seal(
      run,
      termination: .interrupted,
    )

    #expect(try fixture.readHistory().runs.first?.termination == .interrupted)
  }

  @Test
  func `sealing gives back the marker that was published`() throws {
    let run = try open()
    try fixture.writer.append(
      WriterFixture.result(),
      to: run,
    )

    let completion = try fixture.writer.seal(
      run,
      termination: .completed,
    )

    let stored = try fixture.readHistory().runs.first?.completion

    #expect(completion == stored)
    #expect(completion.resultCount == 1)
    #expect(completion.details?.finishedAt == StoreSamples.timestamp)
  }

  @Test
  func `a sealed run is never sealed again, and its marker is untouched`() throws {
    let run = try fixture.recordRun()
    let marker = try fixture.read("\(folder(run))/completion.json")

    #expect(throws: StoreWritingError.sealed(run.identifier)) {
      try fixture.writer.seal(
        run,
        termination: .interrupted,
      )
    }
    #expect(try fixture.read("\(folder(run))/completion.json") == marker)
  }

  @Test
  func `nothing is appended to a sealed run`() throws {
    let run = try fixture.recordRun()
    let log = try fixture.read("\(folder(run))/results.jsonl")

    #expect(throws: StoreWritingError.sealed(run.identifier)) {
      try fixture.writer.append(
        WriterFixture.result(route: "other"),
        to: run,
      )
    }
    #expect(try fixture.read("\(folder(run))/results.jsonl") == log)
  }

  @Test
  func `two results for one use case and route cannot be sealed`() throws {
    let run = try open()
    try fixture.writer.append(
      WriterFixture.result(.pass),
      to: run,
    )
    try fixture.writer.append(
      WriterFixture.result(.fail),
      to: run,
    )

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.seal(
        run,
        termination: .completed,
      )
    }
    #expect(fixture.names(in: folder(run)) == ["results.jsonl", "run.json"])
  }

  @Test
  func `a result of a newer version cannot be appended`() throws {
    let run = try open()
    let envelope = StoredResult(
      useCase: .sample(StoreSamples.useCase),
      route: .sample(StoreSamples.route),
      fingerprint: .sample("a"),
      verdict: .pass,
      detail: nil,
    )

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.append(
        envelope,
        to: run,
      )
    }
    #expect(try fixture.read("\(folder(run))/results.jsonl").isEmpty)
  }

  @Test
  func `a log that lost its last line feed cannot be sealed`() throws {
    let run = try open()
    try fixture.directory.write("\(folder(run))/results.jsonl", "{}")

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.seal(
        run,
        termination: .completed,
      )
    }
  }

  @Test
  func `a manifest that is gone cannot be sealed over`() throws {
    let run = try open()
    try FileManager.default
      .removeItem(at: fixture.directory.location(of: "\(folder(run))/run.json"))

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.seal(
        run,
        termination: .completed,
      )
    }
  }

  @Test
  func `a verify run is sealed with the digest of its start stamp, outputs and reports`() throws {
    let run = try open(kind: .verify)
    try fixture.directory.write("\(folder(run))/start.json", "{\"start\": 1}\n")
    try fixture.directory.write("\(folder(run))/outputs/b-tests/console.txt", "two\n")
    try fixture.directory.write("\(folder(run))/outputs/a-tests/console.txt", "one\n")
    try fixture.directory.write("\(folder(run))/reports/a-tests/report.xml", "<xml/>")

    let completion = try fixture.writer.seal(
      run,
      termination: .completed,
    )

    let details = try #require(completion.details)
    let start = try digest("\(folder(run))/start.json")
    let firstOutput = try digest("\(folder(run))/outputs/a-tests/console.txt")

    #expect(details.startDigest == start)
    #expect(details.outputDigests.map(\.path) == ["a-tests/console.txt", "b-tests/console.txt"])
    #expect(details.outputDigests.first?.digest == firstOutput)
    #expect(details.reportDigests.map(\.path) == ["a-tests/report.xml"])
  }

  @Test
  func `a verify run without a start stamp cannot be sealed`() throws {
    let run = try open(kind: .verify)

    #expect(throws: StoreWritingError.self) {
      try fixture.writer.seal(
        run,
        termination: .completed,
      )
    }
  }
}
