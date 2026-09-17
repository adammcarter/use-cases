/// The evidence commands, declared for help and flag checking. Their port is
/// ladder row 4d; until it lands each one refuses with `cli_not_yet_ported`.
enum EvidenceCommands {
  static let all = [
    record,
    status,
    void,
  ]

  static let record = CommandSpecification(
    unportedPath: ["evidence", "record"],
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
    subrow: "4d",
  )

  static let status = CommandSpecification(
    unportedPath: ["evidence", "status"],
    command: "evidence.status",
    summary: "Replay and report evidence-ledger completeness.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
    subrow: "4d",
  )

  static let void = CommandSpecification(
    unportedPath: ["evidence", "void"],
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
    subrow: "4d",
  )
}
