import MCP
import Testing
@testable import UseCasesMCP

struct ToolCommandLineBuilderSafetyTests {
  private func line(
    _ tool: ToolDefinition,
    _ arguments: [String: Value],
  ) throws -> ToolCommandLine {
    try ToolCommandLineBuilder().commandLine(
      for: tool,
      arguments: arguments,
      workspace: nil,
    )
  }

  @Test
  func `an option value that starts with a dash is joined to its flag, so it is not read as one`(
  ) throws {
    #expect(
      try line(.status, ["group": "-x"]).arguments == ["status", "--json", "--group=-x"],
    )
    #expect(
      try line(.search, ["under": "-duration", "next": "-abc"]).arguments
        == ["search", "--json", "--under=-duration", "--next=-abc"],
    )
    #expect(
      try line(.approve, ["use_cases": ["a"], "by": "-Bob"]).arguments
        == ["approve", "--json", "--by=-Bob", "--", "a"],
    )
    #expect(
      try line(.apply, ["approved_by": "--all", "save": []]).arguments
        == ["apply", "--json", "--approved-by=--all", "--file", "-"],
    )
    #expect(
      try line(.verifyTests, ["step": "finish", "run_id": "-r1"]).arguments
        == ["verify", "--json", "--finish", "--run-id=-r1"],
    )
    #expect(
      try line(.validateFiles, ["workspace": "-w"]).arguments
        == ["validate", "--json", "--workspace=-w"],
    )
  }

  @Test
  func `each value of a repeated option that starts with a dash is joined to its flag`() throws {
    #expect(
      try line(
        .recordVerdict,
        ["use_case": "a", "route": "r", "status": "pass", "attach": ["-x", "y"]],
      ).arguments == ["record", "--json", "--attach=-x", "--attach", "y", "--", "a", "r", "pass"],
    )
  }

  @Test
  func `a list that starts with a dash is joined to its flag as one value`() throws {
    #expect(
      try line(.status, ["state": ["-failed", "stale"]]).arguments
        == ["status", "--json", "--state=-failed,stale"],
    )
  }

  /// A call that holds a text no command line can carry, and the argument that holds it.
  private struct Refusal {
    let tool: ToolDefinition
    let arguments: [String: Value]
    let name: String
  }

  private static let record: [String: Value] = ["use_case": "a", "route": "r", "status": "pass"]

  @Test
  func `a text holding NUL is refused by the argument's name, wherever it would go`() {
    let refused = [
      Refusal(
        tool: .recordVerdict,
        arguments: Self.record.merging(["message": "a\u{0}b"]) { $1 },
        name: "message",
      ),
      Refusal(
        tool: .recordVerdict,
        arguments: Self.record.merging(["attach": ["a\u{0}"]]) { $1 },
        name: "attach",
      ),
      Refusal(tool: .search, arguments: ["query": "pa\u{0}rse"], name: "query"),
      Refusal(tool: .status, arguments: ["group": "g\u{0}"], name: "group"),
      Refusal(tool: .status, arguments: ["target": "\u{0}"], name: "target"),
      Refusal(
        tool: .verifyTests,
        arguments: ["step": "run", "only": ["ok", "no\u{0}"]],
        name: "only",
      ),
      Refusal(tool: .validateFiles, arguments: ["workspace": "/w\u{0}x"], name: "workspace"),
      Refusal(tool: .verifyTests, arguments: ["step": "ru\u{0}n"], name: "step"),
    ]

    for refusal in refused {
      #expect(throws: ToolCommandLineError.holdsNull(argument: refusal.name)) {
        try line(refusal.tool, refusal.arguments)
      }
    }
  }

  @Test
  func `an item of a comma-joined list that holds a comma is refused, it would be two values`() {
    #expect(throws: ToolCommandLineError.holdsComma(argument: "state")) {
      try line(.search, ["query": "x", "state": ["failed,verified"]])
    }
    #expect(throws: ToolCommandLineError.holdsComma(argument: "only")) {
      try line(.verifyTests, ["step": "run", "only": ["a", "b,c"]])
    }
  }

  @Test
  func `a comma is nothing to a value that is not joined`() throws {
    #expect(
      try line(.search, ["query": "a, b"]).arguments == ["search", "--json", "--", "a, b"],
    )
    #expect(
      try line(.recordVerdict, ["use_case": "a", "route": "r", "status": "pass", "attach": ["a,b"]])
        .arguments == ["record", "--json", "--attach", "a,b", "--", "a", "r", "pass"],
    )
  }

  @Test
  func `the refusals say what is wrong, by argument`() {
    #expect(
      ToolCommandLineError.holdsNull(argument: "message").message
        == "message holds a NUL character (U+0000), which a command line cannot carry",
    )
    #expect(
      ToolCommandLineError.holdsComma(argument: "state").message
        == "an item of state holds a comma, which the command would read as two values",
    )
    #expect(
      ToolCommandLineError.unusable(argument: "page_size").message
        == "the value of page_size cannot be passed to the command",
    )
  }
}
