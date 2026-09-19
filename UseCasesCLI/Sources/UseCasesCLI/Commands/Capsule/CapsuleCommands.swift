/// `capsule list|validate|plan|run` (packages/cli/src/commands/capsule.ts).
/// The handlers are in `CapsuleCommands+Runs.swift`.
enum CapsuleCommands {
  static let all = [
    list,
    validate,
    plan,
    run,
  ]

  static let list = CommandSpecification(
    path: ["capsule", "list"],
    command: "capsule.list",
    summary: "List demo capsules.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
  ) { context throws(CommandFailure) in
    try runList(context)
  }

  static let validate = CommandSpecification(
    path: ["capsule", "validate"],
    command: "capsule.validate",
    summary: "Validate demo capsules.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
  ) { context throws(CommandFailure) in
    try runValidate(context)
  }

  static let plan = CommandSpecification(
    path: ["capsule", "plan"],
    command: "capsule.plan",
    summary: "Plan a demo capsule.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      CapsuleFlags.capsule,
    ],
  ) { context throws(CommandFailure) in
    try runPlan(context)
  }

  static let run = CommandSpecification(
    path: ["capsule", "run"],
    command: "capsule.run",
    summary: "Run a demo capsule.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      CapsuleFlags.capsule,
      FlagSpecification(
        key: "executeCommands",
        name: "--execute-commands",
        kind: .boolean,
        summary: "Actually execute the capsule commands.",
      ),
      FlagSpecification(
        key: "idempotencyKey",
        name: "--idempotency-key",
        kind: .string,
        summary: "Idempotency key for the run record.",
        valueName: "<key>",
      ),
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Override the recorded-at timestamp.",
        valueName: "<timestamp>",
      ),
      FlagSpecification(
        key: "commandTimeoutMs",
        name: "--command-timeout-ms",
        kind: .integer,
        summary: "Per-command execution timeout in milliseconds.",
        valueName: "<ms>",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runRun(context)
  }

  /// Every capsule run the CLI records names this host surface.
  static let hostSurface = "codex.cli"
}
