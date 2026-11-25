import MCP
import Testing
@testable import UseCasesMCP

struct ToolCommandLineBuilderTests {
  private func line(
    _ tool: ToolDefinition,
    _ arguments: [String: Value],
    workspace: String? = nil,
  ) throws -> ToolCommandLine {
    try ToolCommandLineBuilder().commandLine(
      for: tool,
      arguments: arguments,
      workspace: workspace,
    )
  }

  @Test
  func `a tool with no arguments is its command with --json`() throws {
    #expect(try line(.validateFiles, [:]).arguments == ["validate", "--json"])
  }

  @Test
  func `a workspace is passed as the option, wherever the tool takes one`() throws {
    #expect(
      try line(.validateFiles, ["workspace": "/w"]).arguments
        == ["validate", "--json", "--workspace", "/w"],
    )
  }

  @Test
  func `a workspace the server was given is the call's own when the call names none`() throws {
    #expect(
      try line(.links, [:], workspace: "/given").arguments
        == ["links", "--json", "--workspace", "/given"],
    )
    #expect(
      try line(.links, ["workspace": "/own"], workspace: "/given").arguments
        == ["links", "--json", "--workspace", "/own"],
    )
  }

  @Test
  func `a tool that takes no workspace is never given one`() throws {
    #expect(try line(.docs, [:], workspace: "/given").arguments == ["docs", "--json"])
  }

  @Test
  func `lists are comma-joined, flags are there when true, and positionals follow --`() throws {
    let status = try line(.status, [
      "target": "checkout.pay",
      "group": "release",
      "state": ["failed", "stale"],
      "gate": false,
      "strict": true,
    ])

    #expect(
      status.arguments == [
        "status", "--json", "--group", "release", "--state", "failed,stale", "--strict", "--",
        "checkout.pay",
      ],
    )
    #expect(status.standardInput == nil)
  }

  @Test
  func `a positional value that starts with a dash is never a flag`() throws {
    let search = try line(.search, ["query": "-format parse"])

    #expect(search.arguments == ["search", "--json", "--", "-format parse"])
  }

  @Test
  func `an integer is passed as its digits, even when written with a fraction of zero`() throws {
    #expect(
      try line(.docs, ["page_size": 5]).arguments == ["docs", "--json", "--page-size", "5"],
    )
    #expect(
      try line(.docs, ["page_size": .double(5.0)]).arguments
        == ["docs", "--json", "--page-size", "5"],
    )
  }

  @Test
  func `the whole of a search is its filters, then its words`() throws {
    let search = try line(.search, [
      "query": "parse",
      "in": ["title", "intent"],
      "under": "duration",
      "tier": ["core", "critical"],
      "exact": true,
      "full": true,
      "page_size": 1,
    ])

    #expect(
      search.arguments == [
        "search", "--json", "--in", "title,intent", "--under", "duration", "--tier",
        "core,critical", "--exact", "--full", "--page-size", "1", "--", "parse",
      ],
    )
  }

  @Test
  func `a search continued carries only its token`() throws {
    #expect(
      try line(.search, ["next": "abc"]).arguments == ["search", "--json", "--next", "abc"],
    )
  }

  @Test
  func `a whole use case to search by is JSON on standard input, read with --like -`() throws {
    let search = try line(.search, ["like": ["title": "Parse a duration"]])

    #expect(search.arguments == ["search", "--json", "--like", "-"])
    #expect(search.standardInput == #"{"title":"Parse a duration"}"#)
  }

  @Test
  func `the steps of verify are flags, and anything else is left to the command line`() throws {
    for step in ["start", "finish", "run", "abort"] {
      #expect(
        try line(.verifyTests, ["step": .string(step)]).arguments
          == ["verify", "--json", "--\(step)"],
      )
    }

    for step in ["walk", "json", "help", "-h", "--run-id", ""] {
      #expect(
        try line(.verifyTests, ["step": .string(step)]).arguments
          == ["verify", "--json", "--", step],
      )
    }
  }

  @Test
  func `verify passes its validations and its run id`() throws {
    #expect(
      try line(.verifyTests, ["step": "finish", "run_id": "0192", "only": ["a", "b"]]).arguments
        == ["verify", "--json", "--finish", "--only", "a,b", "--run-id", "0192"],
    )
  }

  @Test
  func `a verdict is its three words, a note, and one --attach for each file`() throws {
    let record = try line(.recordVerdict, [
      "use_case": "example.getting-started",
      "route": "manual-check",
      "status": "pass",
      "message": "checked by an agent",
      "attach": ["a.png", "b.log"],
    ])

    #expect(
      record.arguments == [
        "record", "--json", "--attach", "a.png", "--attach", "b.log", "--",
        "example.getting-started", "manual-check", "pass", "checked by an agent",
      ],
    )
  }

  @Test
  func `a verdict without a note is three words`() throws {
    #expect(
      try line(.recordVerdict, ["use_case": "a", "route": "r", "status": "fail"]).arguments
        == ["record", "--json", "--", "a", "r", "fail"],
    )
  }

  @Test
  func `a use case saved is JSON on standard input, read with --file -`() throws {
    let save = try line(.save, [
      "use_case": ["id": "a.b.c", "title": "T"],
      "dry_run": true,
    ])

    #expect(save.arguments == ["save", "--json", "--dry-run", "--file", "-"])
    #expect(save.standardInput == #"{"id":"a.b.c","title":"T"}"#)
  }

  @Test
  func `a batch is one JSON object of what was given, and is always read from standard input`(
  ) throws {
    let apply = try line(.apply, [
      "remove": ["a.b.c"],
      "save": [["id": "a.b.d", "title": "T"]],
      "approved_by": "Sam",
      "dry_run": true,
    ])

    #expect(
      apply.arguments == ["apply", "--json", "--approved-by", "Sam", "--dry-run", "--file", "-"],
    )
    #expect(apply.standardInput == #"{"remove":["a.b.c"],"save":[{"id":"a.b.d","title":"T"}]}"#)
    #expect(try line(.apply, [:]).standardInput == "{}")
  }

  @Test
  func `a sign-off is its use cases after --, and who approved`() throws {
    #expect(
      try line(.approve, ["use_cases": ["a", "b"], "by": "Sam", "dry_run": true]).arguments
        == ["approve", "--json", "--by", "Sam", "--dry-run", "--", "a", "b"],
    )
    #expect(
      try line(.approve, ["all": true, "by": "Sam"]).arguments
        == ["approve", "--json", "--all", "--by", "Sam"],
    )
  }

  @Test
  func `a layout is its kind after --, and the intent or proposal on standard input`() throws {
    let render = try line(.render, ["kind": "proposal", "input": ["title": "Rounding"]])

    #expect(render.arguments == ["render", "--json", "--file", "-", "--", "proposal"])
    #expect(render.standardInput == #"{"title":"Rounding"}"#)
  }

  @Test
  func `an empty list is passed as the empty value, for the command line to refuse`() throws {
    #expect(
      try line(.status, ["state": []]).arguments == ["status", "--json", "--state", ""],
    )
  }

  @Test(arguments: [
    ("target", Value.bool(true)),
    ("state", .string("failed")),
    ("state", .array([.bool(true)])),
    ("group", .array([])),
  ])
  func `a value that cannot be written as its argument's text is refused, naming it`(
    name: String,
    value: Value,
  ) {
    #expect(throws: ToolCommandLineError.unusable(argument: name)) {
      try line(.status, [name: value])
    }
  }
}
