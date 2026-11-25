import MCP
import Testing
@testable import UseCasesMCP

struct ToolDefinitionTests {
  private static let names = [
    "use_cases_validate_files", "use_cases_status", "use_cases_verify_tests",
    "use_cases_record_verdict", "use_cases_links", "use_cases_search", "use_cases_show",
    "use_cases_save", "use_cases_remove", "use_cases_apply", "use_cases_approve",
    "use_cases_render", "use_cases_docs",
  ]

  private func definition(_ name: String) throws -> ToolDefinition {
    try #require(ToolDefinition.all.first { $0.name == name })
  }

  @Test
  func `the tools are the thirteen of chapter 20, in its order, and no others`() {
    #expect(ToolDefinition.all.map(\.name) == Self.names)
  }

  @Test(arguments: ["init", "hooks", "mcp", "version", "record_interactive"])
  func `a command a person sets up or needs a terminal for is not a tool`(command: String) {
    #expect(!ToolDefinition.all.map(\.name).contains("use_cases_\(command)"))
    #expect(!ToolDefinition.all.map(\.command).contains(command))
  }

  @Test(arguments: ToolDefinition.all)
  func `every tool is named for what it acts on, titled and described`(
    tool: ToolDefinition,
  ) {
    #expect(tool.name.hasPrefix("use_cases_"))
    #expect(tool.name.allSatisfy { $0.isLowercase || $0 == "_" })
    #expect(!tool.title.isEmpty)
    #expect(tool.description.contains("`use-cases \(tool.command)`"))
  }

  @Test
  func `no two tools share a name or a title`() {
    #expect(Set(ToolDefinition.all.map(\.name)).count == ToolDefinition.all.count)
    #expect(Set(ToolDefinition.all.map(\.title)).count == ToolDefinition.all.count)
  }

  @Test(arguments: ToolDefinition.all)
  func `every input schema takes exactly its arguments and no others`(
    tool: ToolDefinition,
  ) throws {
    let schema = try #require(tool.inputSchema.objectValue)
    let properties = try #require(schema["properties"]?.objectValue)

    #expect(schema["type"] == .string("object"))
    #expect(schema["additionalProperties"] == .bool(false))
    #expect(Set(properties.keys) == Set(tool.arguments.map(\.name)))
    #expect(Set(tool.arguments.map(\.name)).count == tool.arguments.count)
  }

  @Test(arguments: ToolDefinition.all)
  func `every argument says what it is, in a type an agent can send`(
    tool: ToolDefinition,
  ) throws {
    let properties = try #require(tool.inputSchema.objectValue?["properties"]?.objectValue)

    for argument in tool.arguments {
      let property = try #require(properties[argument.name]?.objectValue)

      #expect(property["description"]?.stringValue?.isEmpty == false)
      #expect(property["type"]?.stringValue != nil)
    }
  }

  @Test(arguments: [
    ("use_cases_validate_files", [String]()),
    ("use_cases_status", []),
    ("use_cases_verify_tests", ["step"]),
    ("use_cases_record_verdict", ["use_case", "route", "status"]),
    ("use_cases_links", []),
    ("use_cases_search", []),
    ("use_cases_show", ["use_case"]),
    ("use_cases_save", ["use_case"]),
    ("use_cases_remove", ["use_case"]),
    ("use_cases_apply", []),
    ("use_cases_approve", ["by"]),
    ("use_cases_render", ["kind", "input"]),
    ("use_cases_docs", []),
  ])
  func `every argument is optional except the ones chapter 20 names, in order`(
    name: String,
    required: [String],
  ) throws {
    let schema = try #require(definition(name).inputSchema.objectValue)

    #expect(schema["required"] == .array(required.map(Value.string)))
  }

  @Test
  func `docs needs no workspace and every other tool takes one`() {
    for tool in ToolDefinition.all {
      let takesWorkspace = tool.arguments.contains { $0.name == "workspace" }

      #expect(takesWorkspace == (tool.name != "use_cases_docs"))
    }
  }

  struct Hints: CustomTestStringConvertible {
    let name: String
    let readOnly: Bool
    let destructive: Bool?
    let idempotent: Bool?
    let openWorld: Bool

    var testDescription: String {
      name
    }

    static func readsOnly(_ name: String) -> Hints {
      Hints(name: name, readOnly: true, destructive: nil, idempotent: nil, openWorld: false)
    }

    static func addsOnly(_ name: String) -> Hints {
      Hints(name: name, readOnly: false, destructive: false, idempotent: false, openWorld: false)
    }

    static func runsTests(_ name: String) -> Hints {
      Hints(name: name, readOnly: false, destructive: false, idempotent: false, openWorld: true)
    }

    static func rewrites(_ name: String) -> Hints {
      Hints(name: name, readOnly: false, destructive: true, idempotent: true, openWorld: false)
    }

    static func records(_ name: String) -> Hints {
      Hints(name: name, readOnly: false, destructive: false, idempotent: true, openWorld: false)
    }
  }

  private static let hints: [Hints] = [
    .readsOnly("use_cases_validate_files"),
    .readsOnly("use_cases_status"),
    .runsTests("use_cases_verify_tests"),
    .addsOnly("use_cases_record_verdict"),
    .readsOnly("use_cases_links"),
    .readsOnly("use_cases_search"),
    .readsOnly("use_cases_show"),
    .rewrites("use_cases_save"),
    .rewrites("use_cases_remove"),
    .rewrites("use_cases_apply"),
    .records("use_cases_approve"),
    .readsOnly("use_cases_render"),
    .readsOnly("use_cases_docs"),
  ]

  @Test(arguments: hints)
  func `the annotations say what each tool does to the world`(hints: Hints) throws {
    let annotations = try definition(hints.name).annotations

    #expect(annotations.readOnlyHint == hints.readOnly)
    #expect(annotations.destructiveHint == hints.destructive)
    #expect(annotations.idempotentHint == hints.idempotent)
    #expect(annotations.openWorldHint == hints.openWorld)
  }

  @Test
  func `every tool has its hints stated here`() {
    #expect(Set(Self.hints.map(\.name)) == Set(ToolDefinition.all.map(\.name)))
  }

  @Test
  func `only verify may reach beyond the workspace`() {
    let open = ToolDefinition.all.filter { $0.annotations.openWorldHint == true }

    #expect(open.map(\.name) == ["use_cases_verify_tests"])
  }

  @Test
  func `a step is given by name for the four steps, and the tool lists them`() throws {
    let verify = try definition("use_cases_verify_tests")
    let step = try #require(verify.arguments.first { $0.name == "step" })

    #expect(step.allowedValues == ["start", "finish", "run", "abort"])
    #expect(step.placement == .flagOrPositional(known: ["start", "finish", "run", "abort"]))
  }

  @Test(arguments: ToolDefinition.all)
  func `a tool that reads standard input names what it reads and the flag that says so`(
    tool: ToolDefinition,
  ) {
    let stdinArguments = tool.arguments.filter { $0.placement == .standardInput }.map(\.name)

    switch tool.input {
    case .none:
      #expect(stdinArguments.isEmpty)
    case let .value(argument, flag):
      #expect(stdinArguments == [argument])
      #expect(flag.hasPrefix("--"))
    case let .document(flag):
      #expect(!stdinArguments.isEmpty)
      #expect(flag == "--file")
    }
  }
}
