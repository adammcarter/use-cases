extension ToolDefinition {
  static let validateFiles = ToolDefinition(
    name: "use_cases_validate_files",
    title: "Validate files",
    description: """
    Checks that the authored files (use cases, scopes, groups, bridge settings) are right, and \
    lists the warnings. It runs no test and writes nothing, so it says nothing about whether \
    any behaviour works: use use_cases_verify_tests for that. Runs `use-cases validate`.
    """,
    command: "validate",
    arguments: [.workspace],
    annotations: .readOnly,
    outputSchemaFile: "cli-validate.schema.json",
  )

  static let status = ToolDefinition(
    name: "use_cases_status",
    title: "Status",
    description: """
    Says how far each use case is proven, worst first, or one use case in detail; with `gate`, \
    whether anything blocks. It reports the verdicts stored in this checkout and runs nothing: \
    "unverified" means no verdict here yet, never failed. Runs `use-cases status`.
    """,
    command: "status",
    arguments: [
      .workspace,
      ToolArgument(
        name: "target",
        type: .string,
        placement: .positional,
        description: "A use case id, or the start of an id, to show in detail or list.",
      ),
      ToolArgument(
        name: "group",
        type: .string,
        placement: .option("--group"),
        description: "Only the members of this group.",
      ),
      ToolArgument(
        name: "state",
        type: .stringList,
        placement: .commaSeparated("--state"),
        description: "Only these states, such as failed and stale. draft is a state here.",
        allowedValues: ToolArgument.states,
      ),
      ToolArgument(
        name: "gate",
        type: .boolean,
        placement: .flag("--gate"),
        description: """
        Ask whether anything blocks. A blocked gate is a normal answer (gate.passed is false), \
        not an error. It covers every use case, so it takes no target or state.
        """,
      ),
      ToolArgument(
        name: "strict",
        type: .boolean,
        placement: .flag("--strict"),
        description: "With gate: unverified and incomplete use cases block too.",
      ),
    ],
    annotations: .readOnly,
    outputSchemaFile: "cli-status.schema.json",
  )

  static let links = ToolDefinition(
    name: "use_cases_links",
    title: "Links",
    description: """
    Lists which code and tests each use case is tied to: the file and lines of every link. It \
    shows the ties, not whether the code works. Runs `use-cases links`.
    """,
    command: "links",
    arguments: [
      .workspace,
      ToolArgument(
        name: "target",
        type: .string,
        placement: .positional,
        description: "A use case id, or the start of an id, to list the links of.",
      ),
    ],
    annotations: .readOnly,
    outputSchemaFile: "cli-links.schema.json",
  )

  static let search = ToolDefinition(
    name: "use_cases_search",
    title: "Search use cases",
    description: """
    Finds use cases by words, or by likeness to a whole use case with `like`, best match first, \
    in pages. Use it before adding a use case, to see what already exists or what excludes it. \
    A match is a lead to read with use_cases_show, not proof the use case covers the idea. \
    Give `query` or `like`, or `next` alone for the following page. Runs `use-cases search`.
    """,
    command: "search",
    arguments: [
      .workspace,
      ToolArgument(
        name: "query",
        type: .string,
        placement: .positional,
        description: """
        Words to look for, "a phrase" that must appear, -word to leave out. It may start with -.
        """,
      ),
      ToolArgument(
        name: "like",
        type: .object,
        placement: .standardInput,
        description: """
        A whole use case, as use_cases_show returns it, to find the use cases most like. It need \
        not be valid: a draft is enough.
        """,
      ),
      ToolArgument(
        name: "in",
        type: .stringList,
        placement: .commaSeparated("--in"),
        description: """
        Only these fields: id, title, description, intent, scenarios, out_of_scope, validation. \
        The default is all.
        """,
        allowedValues: [
          "id", "title", "description", "intent", "scenarios", "out_of_scope", "validation",
        ],
      ),
      ToolArgument(
        name: "under",
        type: .string,
        placement: .option("--under"),
        description: "Only use cases under this id prefix.",
      ),
      ToolArgument(
        name: "group",
        type: .string,
        placement: .option("--group"),
        description: "Only the members of this group.",
      ),
      ToolArgument(
        name: "tier",
        type: .stringList,
        placement: .commaSeparated("--tier"),
        description: "Only these value tiers, such as critical and core.",
        allowedValues: ["critical", "core", "supporting"],
      ),
      ToolArgument(
        name: "state",
        type: .stringList,
        placement: .commaSeparated("--state"),
        description: "Only these states, such as failed and stale. draft is a state here.",
        allowedValues: ToolArgument.states,
      ),
      .exact,
      ToolArgument(
        name: "full",
        type: .boolean,
        placement: .flag("--full"),
        description: "Add each match's whole use case to the answer.",
      ),
      .pageSize,
      .next,
    ],
    input: .value(
      argument: "like",
      flag: "--like",
    ),
    annotations: .readOnly,
    outputSchemaFile: "cli-search.schema.json",
  )

  static let show = ToolDefinition(
    name: "use_cases_show",
    title: "Show a use case",
    description: """
    Returns one use case whole, exactly as use_cases_save takes it: show, change a field, save. \
    It also says whether the use case is READY or a draft, what is missing, and whether it is \
    approved. Runs `use-cases show`.
    """,
    command: "show",
    arguments: [
      .workspace,
      ToolArgument(
        name: "use_case",
        type: .string,
        placement: .positional,
        description: "The full id of the use case.",
        isRequired: true,
      ),
    ],
    annotations: .readOnly,
    outputSchemaFile: "cli-show.schema.json",
  )

  static let docs = ToolDefinition(
    name: "use_cases_docs",
    title: "Docs",
    description: """
    Teaches how to use Use Cases and its quirks, from the guides of the version being talked \
    to: no query lists the guides, a guide's name shows it, other words search the sections. It \
    needs no workspace. Runs `use-cases docs`.
    """,
    command: "docs",
    arguments: [
      ToolArgument(
        name: "query",
        type: .string,
        placement: .positional,
        description: "A guide's name to show it, or words to look for in the guides.",
      ),
      .exact,
      .pageSize,
      .next,
    ],
    annotations: .readOnly,
    outputSchemaFile: "cli-docs.schema.json",
  )
}
