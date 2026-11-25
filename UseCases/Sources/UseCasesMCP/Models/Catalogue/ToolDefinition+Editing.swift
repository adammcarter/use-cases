extension ToolDefinition {
  static let save = ToolDefinition(
    name: "use_cases_save",
    title: "Save a use case",
    description: """
    Creates or replaces one use case, whole, as a person's `use-cases save` does: only that \
    use case's lines change, in the file the recommended structure gives it, and nothing is \
    written if the workspace would be INVALID. Comments inside a replaced use case are dropped \
    and listed as warnings. Pass `use_case` as use_cases_show returns it; dry_run previews. \
    Runs `use-cases save`.
    """,
    command: "save",
    arguments: [
      .workspace,
      ToolArgument(
        name: "use_case",
        type: .object,
        placement: .standardInput,
        description: "The whole use case, with its id, as use_cases_show returns it.",
        isRequired: true,
      ),
      .dryRun,
    ],
    input: .value(
      argument: "use_case",
      flag: "--file",
    ),
    annotations: .rewritesFiles,
    outputSchemaFile: "cli-save.schema.json",
  )

  static let remove = ToolDefinition(
    name: "use_cases_remove",
    title: "Remove a use case",
    description: """
    Takes one use case out of its file (the file goes too when it was the last). Its verdicts \
    stay in the store, and markers that still name it are listed as warnings, not changed. \
    Runs `use-cases remove`.
    """,
    command: "remove",
    arguments: [
      .workspace,
      ToolArgument(
        name: "use_case",
        type: .string,
        placement: .positional,
        description: "The full id of the use case.",
        isRequired: true,
      ),
      .dryRun,
    ],
    annotations: .rewritesFiles,
    outputSchemaFile: "cli-remove.schema.json",
  )

  static let apply = ToolDefinition(
    name: "use_cases_apply",
    title: "Apply a batch",
    description: """
    Applies a batch of use case changes all or nothing: every removal, then every addition, then \
    every update, checked once as a whole. Use dry_run first: the preview is what a person signs \
    off, and exactly that batch is what is written. A use case may appear once in a batch. Runs \
    `use-cases apply`.
    """,
    command: "apply",
    arguments: [
      .workspace,
      ToolArgument(
        name: "remove",
        type: .stringList,
        placement: .standardInput,
        description: "The ids of the use cases to remove.",
      ),
      ToolArgument(
        name: "save",
        type: .objectList,
        placement: .standardInput,
        description: "The whole use cases to add or replace, as use_cases_show returns them.",
      ),
      ToolArgument(
        name: "approved_by",
        type: .string,
        placement: .option("--approved-by"),
        description: """
        The name of the person who signed the batch off; each use case it saves is then \
        approved as it now reads. Only a person's name, only for what they approved.
        """,
      ),
      .dryRun,
    ],
    input: .document(flag: "--file"),
    annotations: .rewritesFiles,
    outputSchemaFile: "cli-apply.schema.json",
  )

  static let approve = ToolDefinition(
    name: "use_cases_approve",
    title: "Approve use cases",
    description: """
    Records a person's sign-off on each use case's promise as it reads now, with their name and \
    today's date. Only record what the person approved, under their name; supporting use cases \
    may be approved by an agent only where the person said so. Runs `use-cases approve`.
    """,
    command: "approve",
    arguments: [
      .workspace,
      ToolArgument(
        name: "use_cases",
        type: .stringList,
        placement: .positionalList,
        description: "The use cases to approve.",
      ),
      ToolArgument(
        name: "all",
        type: .boolean,
        placement: .flag("--all"),
        description: "Approve every use case as it reads now, instead of a list.",
      ),
      ToolArgument(
        name: "by",
        type: .string,
        placement: .option("--by"),
        description: "The name of the person who approved.",
        isRequired: true,
      ),
      .dryRun,
    ],
    annotations: .recordsOnce,
    outputSchemaFile: "cli-approve.schema.json",
  )

  static let render = ToolDefinition(
    name: "use_cases_render",
    title: "Render a layout",
    description: """
    Draws a canonical layout for the person to read: pass the intent or the proposal, and show \
    the returned `text` as it is. It changes nothing. Every layout but the intent reads the \
    workspace: ids and the pointers of the proposal are checked against it, and a proposal \
    `apply` would refuse is refused with the same message. Results are drawn only after the \
    proposal is applied. Runs `use-cases render`.
    """,
    command: "render",
    arguments: [
      .workspace,
      ToolArgument(
        name: "kind",
        type: .string,
        placement: .positional,
        description: "The layout: intent, brief, proposal or results.",
        isRequired: true,
        allowedValues: ["intent", "brief", "proposal", "results"],
      ),
      ToolArgument(
        name: "input",
        type: .object,
        placement: .standardInput,
        description: "What to draw: the intent, or the proposal, as chapter 21 describes it.",
        isRequired: true,
      ),
    ],
    input: .value(
      argument: "input",
      flag: "--file",
    ),
    annotations: .readOnly,
    outputSchemaFile: "cli-render.schema.json",
  )
}
