import Testing
@testable import UseCasesCore

struct RunOrderFileTests {
  @Test
  func `the file is the line chapter 12 shows, with no line feed`() {
    let order = RunOrder(lastRunIdentifier: .sample(42))

    #expect(
      order.fileBytes.utf8Text
        == #"{"order_version":1,"last_run_id":"0000000000000000000000000000002a"}"#,
    )
  }

  @Test
  func `the reader reads the mark back`() throws {
    let fixture = try StoreFixture()
    let order = RunOrder(lastRunIdentifier: .sample(42))
    try fixture.write(
      ".use-cases/run-order.json",
      order.fileBytes.utf8Text,
    )

    #expect(try RunOrderReader().readRunOrder(in: fixture.workspace) == order)
  }
}
