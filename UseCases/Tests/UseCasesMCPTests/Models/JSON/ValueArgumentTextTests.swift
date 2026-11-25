import MCP
import Testing
@testable import UseCasesMCP

struct ValueArgumentTextTests {
  @Test(arguments: [
    (Value.string("text"), "text"),
    (.string(""), ""),
    (.int(5), "5"),
    (.int(-1), "-1"),
    (.double(5.0), "5"),
    (.double(-3.0), "-3"),
  ])
  func `a scalar is the text a command line takes`(
    value: Value,
    expected: String,
  ) {
    #expect(value.argumentText == expected)
  }

  @Test(arguments: [
    Value.bool(true), .null, .array([]), .object([:]), .double(5.5), .double(.infinity),
    .double(.nan), .double(1e30),
  ])
  func `anything else is not text`(value: Value) {
    #expect(value.argumentText == nil)
  }
}
