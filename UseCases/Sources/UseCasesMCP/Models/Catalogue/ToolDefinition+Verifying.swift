extension ToolDefinition {
  static let verifyTests = ToolDefinition(
    name: "use_cases_verify_tests",
    title: "Verify tests",
    description: """
    Gets verdicts from the project's own tests. step `run` does it all: it starts a run, runs the \
    commands of the bridge settings and reads their reports, and it can take as long as the \
    tests do. `start` then `finish` is the same in two steps, for tests run another way. A run \
    sealed with run errors, or a failed test, is a normal answer, not a tool error: read the \
    verdicts and errors in it. Runs `use-cases verify`.
    """,
    command: "verify",
    arguments: [
      .workspace,
      ToolArgument(
        name: "step",
        type: .string,
        placement: .flagOrPositional(known: Self.verifySteps),
        description: """
        start: note the code and name where each report goes. finish: read the reports of a \
        started run. run: start, run the commands, finish. abort: close a started run nobody \
        will finish.
        """,
        isRequired: true,
        allowedValues: Self.verifySteps,
      ),
      ToolArgument(
        name: "only",
        type: .stringList,
        placement: .commaSeparated("--only"),
        description: "Read only these validations (with start and run).",
      ),
      ToolArgument(
        name: "run_id",
        type: .string,
        placement: .option("--run-id"),
        description: "The run to finish or close (with finish and abort).",
      ),
    ],
    annotations: .runsTests,
    outputSchemaFile: "cli-verify.schema.json",
  )

  static let recordVerdict = ToolDefinition(
    name: "use_cases_record_verdict",
    title: "Record a verdict",
    description: """
    Records one verdict for one route of one use case, exactly as a person's `use-cases record` \
    does: use it for a check done by hand, never to make a failing test pass. The verdict counts \
    like any other and nothing marks that an agent recorded it. Runs `use-cases record`.
    """,
    command: "record",
    arguments: [
      .workspace,
      ToolArgument(
        name: "use_case",
        type: .string,
        placement: .positional,
        description: "The use case, or an unambiguous start of its id.",
        isRequired: true,
      ),
      ToolArgument(
        name: "route",
        type: .string,
        placement: .positional,
        description: "The route of that use case the verdict is for.",
        isRequired: true,
      ),
      ToolArgument(
        name: "status",
        type: .string,
        placement: .positional,
        description: "The verdict: pass, fail, incomplete or error.",
        isRequired: true,
        allowedValues: ["pass", "fail", "incomplete", "error"],
      ),
      ToolArgument(
        name: "message",
        type: .string,
        placement: .positional,
        description: "A note that goes with the verdict.",
      ),
      ToolArgument(
        name: "attach",
        type: .stringList,
        placement: .repeated("--attach"),
        description: "Files to keep with the verdict as evidence.",
      ),
    ],
    annotations: .additive,
    outputSchemaFile: "cli-record.schema.json",
  )

  private static let verifySteps = ["start", "finish", "run", "abort"]
}
