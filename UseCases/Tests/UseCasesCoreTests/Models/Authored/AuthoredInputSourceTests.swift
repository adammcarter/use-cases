import Testing
@testable import UseCasesCore

struct AuthoredInputSourceTests {
  @Test
  func `a dash is the standard input, called stdin`() {
    let source = AuthoredInputSource(argument: "-")

    #expect(source == .standardInput)
    #expect(source.name == "stdin")
  }

  @Test(arguments: ["new.yml", "./-", "--", "-x", "dir/-", ""])
  func `anything else is a file, called by the path as it was typed`(argument: String) {
    let source = AuthoredInputSource(argument: argument)

    #expect(source == .file(argument))
    #expect(source.name == argument)
  }
}
