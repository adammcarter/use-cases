/// `evidence record|status|void` (packages/cli/src/commands/evidence.ts).
/// Recording is in `EvidenceCommands+Record.swift`, with the performed run in
/// ``EvidencePerformedCommand``; status and void each have their own file.
enum EvidenceCommands {
  static let all = [
    record,
    status,
    void,
  ]

  static let record = CommandSpecification(
    path: ["evidence", "record"],
    command: "evidence.record",
    summary: "Record an evidence event for a use case.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      FlagSpecification(
        key: "useCase",
        name: "--use-case",
        kind: .string,
        summary: "Use-case id to attach evidence to.",
        valueName: "<id>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "kind",
        name: "--kind",
        kind: .string,
        summary: "Evidence kind (defaults to manual_observation).",
        valueName: "<kind>",
      ),
      FlagSpecification(
        key: "result",
        name: "--result",
        kind: .string,
        summary: "Evidence result (defaults to observed).",
        valueName: "<result>",
      ),
      FlagSpecification(
        key: "summary",
        name: "--summary",
        kind: .string,
        summary: "Human summary of the evidence.",
        valueName: "<text>",
      ),
      FlagSpecification(
        key: "idempotencyKey",
        name: "--idempotency-key",
        kind: .string,
        summary: "Idempotency key (defaults to a derived cli: key).",
        valueName: "<key>",
      ),
      FlagSpecification(
        key: "perform",
        name: "--perform",
        kind: .boolean,
        summary: "PERFORM the behaviour: everything after `--` is spawned here, and the "
          + "exit code + output digests become the evidence. Without it, a record "
          + "is only your word for it.",
      ),
    ],
  ) { context async throws(CommandFailure) in
    try await runRecord(context)
  }

  static let status = CommandSpecification(
    path: ["evidence", "status"],
    command: "evidence.status",
    summary: "Replay and report evidence-ledger completeness.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
  ) { context throws(CommandFailure) in
    try runStatus(context)
  }

  static let void = CommandSpecification(
    path: ["evidence", "void"],
    command: "evidence.void",
    summary: "Void an evidence aggregate at its expected head.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      FlagSpecification(
        key: "evidence",
        name: "--evidence",
        kind: .string,
        summary: "Evidence aggregate id to void.",
        valueName: "<id>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "expectedHead",
        name: "--expected-head",
        kind: .string,
        summary: "Optimistic-concurrency guard (current head event id).",
        valueName: "<event-id>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: "Why the evidence is being voided.",
        valueName: "<text>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "idempotencyKey",
        name: "--idempotency-key",
        kind: .string,
        summary: "Idempotency key (defaults to a derived cli:void: key).",
        valueName: "<key>",
      ),
    ],
  ) { context async throws(CommandFailure) in
    try await runVoid(context)
  }

  /// Every evidence event the CLI appends names this host surface.
  static let hostSurface = "codex.cli"

  /// A string flag's value, or nil when absent.
  static func string(_ value: ParsedFlagValue?) -> String? {
    guard case let .string(text) = value else {
      return nil
    }
    return text
  }

  /// An error envelope with exit 2.
  static func refusal(
    _ command: String,
    _ code: String,
    _ message: String,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(command: command, code: code, message: message),
      exitCode: 2,
    )
  }
}
