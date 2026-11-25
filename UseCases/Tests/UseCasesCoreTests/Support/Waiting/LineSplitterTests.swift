import Testing
@testable import UseCasesTestSupport

struct LineSplitterTests {
  @Test
  func `bytes cut anywhere make the same lines, each without its newline`() {
    var splitter = LineSplitter()

    #expect(splitter.lines(completedBy: Array("ab".utf8)).isEmpty)
    #expect(splitter.lines(completedBy: Array("c\nde".utf8)) == ["abc"])
    #expect(splitter.lines(completedBy: Array("f\n\ng".utf8)) == ["def", ""])
    #expect(splitter.lines(completedBy: Array("\n".utf8)) == ["g"])
  }

  @Test
  func `a line is held back until its newline arrives`() {
    var splitter = LineSplitter()

    for byte in "half".utf8 {
      #expect(splitter.lines(completedBy: [byte]).isEmpty)
    }

    #expect(splitter.lines(completedBy: Array("\n".utf8)) == ["half"])
  }
}
