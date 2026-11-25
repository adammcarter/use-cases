import Foundation
import Testing
@testable import UseCasesCore

struct RunOrderReaderTests {
  let fixture: StoreFixture

  init() throws {
    fixture = try StoreFixture()
  }

  @Test
  func `a store with no allocation file is valid and has no mark`() throws {
    #expect(try RunOrderReader().readRunOrder(in: fixture.workspace) == nil)
  }

  @Test
  func `the high-water mark is read`() throws {
    try fixture.write(".use-cases/run-order.json", StoreSamples.runOrder.json)

    let order = try RunOrderReader().readRunOrder(in: fixture.workspace)

    #expect(order?.lastRunIdentifier.text == StoreSamples.runIdentifier)
  }

  @Test
  func `a malformed allocation file is an error, never a reset`() throws {
    try fixture.write(".use-cases/run-order.json", "{")

    let error = #expect(throws: StoreProblem.self) {
      try RunOrderReader().readRunOrder(in: fixture.workspace)
    }

    #expect(error?.description.hasPrefix(".use-cases/run-order.json is corrupt: ") == true)
  }

  @Test(arguments: [
    #"{"order_version":1}"#,
    #"{"order_version":1,"last_run_id":"2a"}"#,
    #"{"order_version":1,"last_run_id":"00000000000000000000000000000000"}"#,
    #"{"order_version":0,"last_run_id":"0000000000000000000000000000002a"}"#,
    #"[]"#,
  ])
  func `an allocation file that breaks its schema is corrupt`(text: String) throws {
    try fixture.write(".use-cases/run-order.json", text)

    #expect(throws: StoreProblem.self) {
      try RunOrderReader().readRunOrder(in: fixture.workspace)
    }
  }

  @Test
  func `a member of a version this core reads that it does not know is ignored`() throws {
    try fixture.write(
      ".use-cases/run-order.json",
      StoreSamples.runOrder.setting("extra", "1").json,
    )

    let order = try RunOrderReader().readRunOrder(in: fixture.workspace)

    #expect(order?.lastRunIdentifier.text == StoreSamples.runIdentifier)
  }

  @Test
  func `an allocation file of a newer version is unsupported`() throws {
    try fixture.write(
      ".use-cases/run-order.json",
      StoreSamples.runOrder.setting("order_version", "2").json,
    )

    #expect(throws: StoreProblem.unsupported(
      ".use-cases/run-order.json",
      "order_version 2 is newer than this core reads",
    )) {
      try RunOrderReader().readRunOrder(in: fixture.workspace)
    }
  }

  @Test
  func `a symlinked allocation file is not followed`() throws {
    try fixture.write("elsewhere.json", StoreSamples.runOrder.json)
    try fixture.directory.symlink(".use-cases/run-order.json", to: "../elsewhere.json")

    #expect(throws: StoreProblem.corrupt(
      ".use-cases/run-order.json",
      "it is a symlink, not a file",
    )) {
      try RunOrderReader().readRunOrder(in: fixture.workspace)
    }
  }

  @Test
  func `reading the history ignores a bad allocation file`() throws {
    try fixture.sealRecord(StoreFixture.identifier(1))
    try fixture.write(".use-cases/run-order.json", "garbage")

    let history = try StoreReader().readHistory(in: fixture.workspace)

    #expect(history.runs.count == 1)
  }
}
