import Foundation
import Testing
@testable import UseCasesCore

struct RunWriterAllocationTests {
  private let fixture: WriterFixture

  init() throws {
    fixture = try WriterFixture()
  }

  @discardableResult
  private func open(in fixture: WriterFixture? = nil) throws -> RunIdentifier {
    let used = fixture ?? self.fixture

    return try used.writer.openRun(
      kind: .record,
      in: used.workspace,
    ).identifier
  }

  @Test
  func `ids only go up even when the clock says the same time`() throws {
    let first = try open()
    let second = try open()
    let third = try open()

    #expect(first < second)
    #expect(second < third)
    #expect(RunNumber(identifier: second) == RunNumber(identifier: first).successor)
  }

  @Test
  func `a clock that has gone back still allocates above the high-water mark`() throws {
    let later = try WriterFixture(clock: FixedTimekeeper(milliseconds: 2_000_000_000_000))
    let first = try open(in: later)

    let earlier = FixedTimekeeper(milliseconds: 1_000_000_000_000)
    let back = try RunWriter(
      clock: earlier,
      random: FixedRandomBits(),
    )
    let second = try back.openRun(
      kind: .record,
      in: later.workspace,
    ).identifier

    #expect(second > first)
    #expect(RunNumber(identifier: second) == RunNumber(identifier: first).successor)
  }

  @Test
  func `a mark in run-order.json above the clock is allocated above`() throws {
    let mark = try RunIdentifier(validating: "ffff00000000000000000000000000ff")
    try fixture.directory.write(
      ".use-cases/run-order.json",
      RunOrder(lastRunIdentifier: mark).fileBytes.utf8Text,
    )

    let run = try open()

    #expect(run > mark)
    #expect(RunNumber(identifier: run) == RunNumber(identifier: mark).successor)
  }

  @Test
  func `a store without run-order.json continues above the greatest run folder`() throws {
    let greatest = try RunIdentifier(validating: "ffff00000000000000000000000000ff")
    try fixture.directory.write(".use-cases/runs/\(greatest.text)/run.json", "{}")
    try fixture.directory.write(".use-cases/runs/\(StoreFixture.identifier(9))/run.json", "{}")

    let run = try open()

    #expect(run > greatest)
  }

  @Test
  func `a deleted run never lowers the next id`() throws {
    try open()
    let last = try open()
    try FileManager.default
      .removeItem(at: fixture.directory.location(of: ".use-cases/runs/\(last.text)"))

    let next = try open()

    #expect(next > last)
  }

  @Test
  func `a temporary folder, a stray file and a stray folder in runs are not run ids`() throws {
    try fixture.directory.write(".use-cases/runs/.tmp-abandoned/run.json", "{}")
    try fixture.directory.write(".use-cases/runs/notes.txt", "hello")
    try fixture.directory.makeDirectory(".use-cases/runs/latest")

    let run = try open()

    #expect(run.text == "01a0d88fc5fbcdef0123456789abcdef")
  }

  @Test
  func `a malformed run-order.json refuses allocation and writes nothing`() throws {
    try fixture.directory.write(".use-cases/run-order.json", #"{"order_version":1}"#)

    let error = #expect(throws: StoreWritingError.self) {
      try open()
    }

    guard case .allocation? = error else {
      Issue.record("expected an allocation error, got \(String(describing: error))")
      return
    }

    #expect(try fixture.read(".use-cases/run-order.json") == #"{"order_version":1}"#)
    #expect(fixture.names(in: ".use-cases") == ["run-order.json"])
  }

  @Test
  func `a run-order.json of a newer version refuses allocation and writes nothing`() throws {
    let newer = #"{"order_version":2,"last_run_id":"0000000000000000000000000000002a"}"#
    try fixture.directory.write(".use-cases/run-order.json", newer)

    #expect(throws: StoreWritingError.self) {
      try open()
    }
    #expect(try fixture.read(".use-cases/run-order.json") == newer)
    #expect(fixture.names(in: ".use-cases/runs").isEmpty)
  }

  @Test
  func `a run-order.json that is not JSON refuses allocation`() throws {
    try fixture.directory.write(".use-cases/run-order.json", "not json")

    #expect(throws: StoreWritingError.self) {
      try open()
    }
  }

  @Test
  func `the greatest id there is cannot be allocated above`() throws {
    let greatest = try RunIdentifier(validating: String(repeating: "f", count: 32))
    try fixture.directory.write(
      ".use-cases/run-order.json",
      RunOrder(lastRunIdentifier: greatest).fileBytes.utf8Text,
    )

    #expect(throws: StoreWritingError.identifiersExhausted) {
      try open()
    }
  }

  @Test
  func `the high-water mark is on disk before the run is published`() throws {
    let failing = try RunWriter(
      clock: FixedTimekeeper(),
      random: FixedRandomBits(),
      files: PublishFailingFileWriter(),
    )

    #expect(throws: StoreWritingError.self) {
      try failing.openRun(
        kind: .record,
        in: fixture.workspace,
      )
    }

    let mark = try #require(try RunOrderReader().readRunOrder(in: fixture.workspace))
    #expect(mark.lastRunIdentifier.text == "01a0d88fc5fbcdef0123456789abcdef")
    #expect(fixture.names(in: ".use-cases/runs").isEmpty)
  }

  @Test
  func `a run folder above the mark, as a merged store has, is allocated above`() throws {
    let mark = RunIdentifier.sample(5)
    let above = try RunIdentifier(validating: "ffff00000000000000000000000000ff")
    try fixture.directory.write(
      ".use-cases/run-order.json",
      RunOrder(lastRunIdentifier: mark).fileBytes.utf8Text,
    )
    try fixture.directory.write(".use-cases/runs/\(above.text)/run.json", "{}")

    let run = try open()

    #expect(RunNumber(identifier: run) == RunNumber(identifier: above).successor)
  }

  @Test
  func `a refused allocation leaves nothing behind but what was there`() throws {
    try fixture.directory.write(".use-cases/run-order.json", #"{"order_version":1}"#)

    #expect(throws: StoreWritingError.self) {
      try open()
    }
    #expect(fixture.names(in: ".use-cases") == ["run-order.json"])
  }

  @Test
  func `a runs folder that is a symlink is said to be one`() throws {
    try fixture.directory.makeDirectory("elsewhere")
    try fixture.directory.symlink(
      ".use-cases/runs",
      to: fixture.directory.location(of: "elsewhere").path,
    )

    let error = #expect(throws: StoreWritingError.self) {
      try open()
    }

    #expect(error?.description.contains("it is a symlink, not a folder") == true)
    #expect(fixture.names(in: "elsewhere").isEmpty)
  }
}
