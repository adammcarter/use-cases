/// The capsule commands, declared for help and flag checking. Their port is
/// ladder row 4e; until it lands each one refuses with `cli_not_yet_ported`.
enum CapsuleCommands {
  static let all = [
    list,
    validate,
    plan,
    run,
  ]

  static let list = CommandSpecification(
    unportedPath: ["capsule", "list"],
    command: "capsule.list",
    summary: "List demo capsules.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
    subrow: "4e",
  )

  static let validate = CommandSpecification(
    unportedPath: ["capsule", "validate"],
    command: "capsule.validate",
    summary: "Validate demo capsules.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
    subrow: "4e",
  )

  static let plan = CommandSpecification(
    unportedPath: ["capsule", "plan"],
    command: "capsule.plan",
    summary: "Plan a demo capsule.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      CapsuleFlags.capsule,
    ],
    subrow: "4e",
  )

  static let run = CommandSpecification(
    unportedPath: ["capsule", "run"],
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
    subrow: "4e",
  )
}
