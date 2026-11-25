import MCP
import Testing
@testable import UseCasesMCP

struct JSONValueWriterTests {
  private let writer = JSONValueWriter()

  @Test
  func `members come in key order, on one line, with slashes as they are`() {
    let value: Value = ["b": 1, "a": ["x/y", true, nil]]

    #expect(writer.text(of: value) == #"{"a":["x/y",true,null],"b":1}"#)
  }

  @Test
  func `a number JSON has no spelling for cannot be written`() {
    #expect(writer.text(of: .double(.infinity)) == nil)
    #expect(writer.text(of: .double(.nan)) == nil)
  }

  @Test(arguments: [Value.string("a\"b\\c\n\u{1}"), .string("caf\u{E9} \u{1F600}"), .int(Int.max)])
  func `what is written reads back as the value it was`(value: Value) {
    let text = writer.text(of: value)

    #expect(text.flatMap(JSONValueReader().value(of:)) == value)
  }
}
