import Testing
@testable import UseCasesCLI

struct CommandResultRefusalTests {
  @Test
  func `a refusal exits 2 and tells a person on stderr`() {
    let result = CommandResult.refusal(
      .invalid,
      message: "a.yml: one\nb.yml: two",
      command: "validate",
      json: false,
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError == "error: a.yml: one\nb.yml: two\n")
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func `with json the same message is also the document on stdout`() {
    let result = CommandResult.refusal(
      .invalid,
      message: "a.yml: one",
      command: "validate",
      json: true,
    )

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("a.yml: one"))
    #expect(result.standardOutput.hasSuffix("}\n"))
    #expect(result.standardOutput.contains("\"message\" : \"a.yml: one\""))
  }

  @Test
  func `a finished command writes its output with one line break and nothing on stderr`() {
    #expect(CommandResult.done("text").standardOutput == "text\n")
    #expect(CommandResult.done("text\n").standardOutput == "text\n")
    #expect(CommandResult.done("text").standardError.isEmpty)
    #expect(CommandResult.done("text").exitCode == 0)
  }
}
