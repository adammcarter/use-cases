import MCP
import Testing
import UseCasesCore
@testable import UseCasesMCP

struct ToolResultMapperTests {
  private let mapper = ToolResultMapper()

  private func outcome(
    _ ending: CommandEnding,
    out: String = "",
    err: String = "",
  ) -> CommandOutcome {
    CommandOutcome(
      ending: ending,
      standardOutput: out,
      standardError: err,
    )
  }

  private func text(of result: CallTool.Result) -> String? {
    guard case let .text(text, _, _)? = result.content.first else {
      return nil
    }

    return text
  }

  private let document = [
    "{", #"  "command" : "status","#, #"  "output_version" : 1,"#, #"  "n" : 1.0"#, "}", "",
  ].joined(separator: "\n")

  @Test(arguments: [0, 1] as [Int32])
  func `a document at exit 0 or 1 is the answer, as printed and as structured content`(
    code: Int32,
  ) throws {
    let result = mapper.result(
      for: outcome(.exited(code), out: document),
      command: "status",
    )

    #expect(result.isError == false)
    #expect(text(of: result) == document)
    #expect(result.content.count == 1)
    let members = try #require(result.structuredContent?.objectValue)
    #expect(members["command"] == "status")
    #expect(members["output_version"] == 1)
    #expect(members["n"] == .double(1.0) || members["n"] == .int(1))
  }

  @Test
  func `isError is said explicitly for an answer, never left out`() {
    let result = mapper.result(
      for: outcome(.exited(0), out: document),
      command: "status",
    )

    #expect(result.isError != nil)
  }

  @Test
  func `a document with an error is a tool error, as text, with nothing structured`() {
    let refusal = [
      #"{"output_version":1,"command":"verify","#,
      #""error":{"kind":"refused","message":"no started run"}}"#,
      "",
    ].joined(separator: "\n")

    let result = mapper.result(
      for: outcome(.exited(2), out: refusal, err: "error: no started run\n"),
      command: "verify",
    )

    #expect(result.isError == true)
    #expect(text(of: result) == refusal)
    #expect(result.structuredContent == nil)
  }

  @Test
  func `a refusal is a tool error whatever exit code carried it`() {
    let refusal = #"{"command":"verify","error":{"kind":"cancelled","message":"stopped"}}"#

    for code: Int32 in [0, 1, 2, 130] {
      let result = mapper.result(
        for: outcome(.exited(code), out: refusal),
        command: "verify",
      )

      #expect(result.isError == true)
      #expect(result.structuredContent == nil)
    }
  }

  @Test
  func `a sealed run that was cancelled, exit 130, is a normal answer`() {
    let sealed = [
      #"{"output_version":1,"command":"verify","step":"run","#,
      #""cancelled":true,"results":[]}"#,
    ].joined()

    let result = mapper.result(
      for: outcome(.exited(130), out: sealed),
      command: "verify",
    )

    #expect(result.isError == false)
    #expect(text(of: result) == sealed)
    #expect(result.structuredContent?.objectValue?["cancelled"] == true)
  }

  @Test
  func `a document at exit 130 that does not say it was cancelled is not an answer`() {
    let result = mapper.result(
      for: outcome(.exited(130), out: #"{"command":"verify"}"#),
      command: "verify",
    )

    #expect(result.isError == true)
    #expect(result.structuredContent == nil)
  }

  @Test(arguments: [2, 3, 4, 127] as [Int32])
  func `a document at any other exit code is a tool error`(code: Int32) {
    let result = mapper.result(
      for: outcome(.exited(code), out: document),
      command: "status",
    )

    #expect(result.isError == true)
    #expect(text(of: result) == document)
    #expect(result.structuredContent == nil)
  }

  @Test
  func `a command that printed no document is a tool error saying what it wrote to stderr`() {
    let result = mapper.result(
      for: outcome(.exited(3), err: "use-cases save is not built yet\n"),
      command: "save",
    )

    #expect(result.isError == true)
    #expect(text(of: result) == "use-cases save is not built yet\n")
    #expect(result.structuredContent == nil)
  }

  @Test(arguments: ["", "not json", "[1, 2]", "42", "\"text\"", "{\"a\":", "{} {}"])
  func `output that is not one JSON object is no document`(printed: String) {
    let result = mapper.result(
      for: outcome(.exited(0), out: printed, err: "trouble\n"),
      command: "status",
    )

    #expect(result.isError == true)
    #expect(text(of: result) == "trouble\n")
    #expect(result.structuredContent == nil)
  }

  @Test
  func `no document and nothing on stderr still says how the command ended`() {
    let exited = mapper.result(for: outcome(.exited(3)), command: "save")
    let signalled = mapper.result(for: outcome(.signaled(9)), command: "save")

    #expect(text(of: exited) == "use-cases save ended with exit code 3 and printed no document")
    #expect(text(of: signalled) == "use-cases save was stopped by signal 9 and printed no document")
  }

  @Test
  func `a large document is given whole`() {
    let list = Array(repeating: "\"padding padding padding\"", count: 100_000)
      .joined(separator: ",")
    let large = ["{\"items\":[", list, "]}"].joined()

    let result = mapper.result(
      for: outcome(.exited(0), out: large),
      command: "search",
    )

    #expect(text(of: result) == large)
    #expect(result.structuredContent?.objectValue?["items"]?.arrayValue?.count == 100_000)
  }

  @Test
  func `a refusal of the server's own is the command line's error document, a tool error`() {
    let result = mapper.refusal(.usage(command: "verify", message: "needs step"))

    #expect(result.isError == true)
    #expect(result.structuredContent == nil)
    #expect(
      text(of: result)
        ==
        #"{"command":"verify","error":{"kind":"usage","message":"needs step"},"output_version":1}"#,
    )
  }

  @Test
  func `the warnings of a sign-off are in the structured content, as the command printed them`()
    throws
  {
    let approve = [
      "{", #"  "by" : "Sam","#, #"  "changes" : [],"#, #"  "command" : "approve","#,
      #"  "dry_run" : false,"#, #"  "output_version" : 1,"#, #"  "use_cases" : [],"#,
      #"  "warnings" : ["use-cases/a.yml:5: the comment # who is dropped"]"#, "}", "",
    ].joined(separator: "\n")

    let result = mapper.result(
      for: outcome(.exited(0), out: approve),
      command: "approve",
    )

    let members = try #require(result.structuredContent?.objectValue)
    #expect(members["warnings"] == ["use-cases/a.yml:5: the comment # who is dropped"])
    #expect(text(of: result) == approve)
  }
}
