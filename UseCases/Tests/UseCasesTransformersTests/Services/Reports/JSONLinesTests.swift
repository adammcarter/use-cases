import Testing
@testable import UseCasesTransformers

struct JSONLinesTests {
  @Test
  func `each line is read as JSON, with its line number`() {
    let lines = JSONLines(text: "{\"a\": 1}\n[2]\n\"three\"\n").lines

    #expect(lines.map(\.number) == [1, 2, 3])
    #expect(lines[0].value?["a"]?.integerValue == 1)
    #expect(lines[1].value?.arrayValue == [.integer(2)])
    #expect(lines[2].value?.stringValue == "three")
  }

  @Test
  func `blank lines are skipped but still counted`() {
    let lines = JSONLines(text: "{}\n\n   \n{}").lines

    #expect(lines.map(\.number) == [1, 4])
  }

  @Test
  func `a line that is not JSON has no value`() {
    let lines = JSONLines(text: "{}\nplain text\n{\"half\":\n").lines

    #expect(lines.map(\.number) == [1, 2, 3])
    #expect(lines.map { $0.value == nil } == [false, true, true])
  }

  @Test
  func `windows line endings are line breaks too`() {
    #expect(JSONLines(text: "{}\r\n{}\r\n").lines.map(\.number) == [1, 2])
  }

  @Test
  func `an empty report has no lines`() {
    #expect(JSONLines(text: "").lines.isEmpty)
  }
}
