/// The matrix commands, declared for help and flag checking. Their port is
/// ladder row 4b; until it lands each one refuses with `cli_not_yet_ported`.
enum MatrixCommands {
  static let all = [
    validate,
    list,
    status,
    upsert,
    remove,
  ]

  static let validate = CommandSpecification(
    unportedPath: ["matrix", "validate"],
    command: "matrix.validate",
    summary: "Validate the use-case matrix.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
    subrow: "4b",
  )

  static let list = CommandSpecification(
    unportedPath: ["matrix", "list"],
    command: "matrix.list",
    summary: "Query and list use cases.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      FlagSpecification(
        key: "value",
        name: "--value",
        kind: .string,
        summary: "Filter by value tier (repeatable).",
        valueName: "<tier>",
        isRepeatable: true,
      ),
      FlagSpecification(
        key: "journeyRole",
        name: "--journey-role",
        kind: .string,
        summary: "Filter by journey role (repeatable).",
        valueName: "<role>",
        isRepeatable: true,
      ),
      FlagSpecification(
        key: "lifecycle",
        name: "--lifecycle",
        kind: .string,
        summary: "Filter by lifecycle (repeatable).",
        valueName: "<state>",
        isRepeatable: true,
      ),
      FlagSpecification(
        key: "host",
        name: "--host",
        kind: .string,
        summary: "Filter by host surface (repeatable).",
        valueName: "<surface>",
        isRepeatable: true,
      ),
      FlagSpecification(
        key: "tag",
        name: "--tag",
        kind: .string,
        summary: "Filter by tag (repeatable).",
        valueName: "<tag>",
        isRepeatable: true,
      ),
      FlagSpecification(
        key: "changedPath",
        name: "--changed-path",
        kind: .string,
        summary: "Filter by changed path (repeatable).",
        valueName: "<path>",
        isRepeatable: true,
      ),
      FlagSpecification(
        key: "strict",
        name: "--strict",
        kind: .boolean,
        summary: "Fail when the matrix is incomplete.",
      ),
    ],
    subrow: "4b",
  )

  static let status = CommandSpecification(
    unportedPath: ["matrix", "status"],
    command: "matrix.status",
    summary: "Compose matrix and evidence completeness.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
    ],
    subrow: "4b",
  )

  static let upsert = CommandSpecification(
    unportedPath: ["matrix", "upsert"],
    command: "matrix.upsert",
    summary: "Add or update a single use-case row.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      FlagSpecification(
        key: "file",
        name: "--file",
        kind: .string,
        summary: "Target use-case file (inside use-cases/).",
        valueName: "<path>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "useCaseJson",
        name: "--use-case-json",
        kind: .string,
        summary: "Inline JSON for the use-case row.",
        valueName: "<json>",
      ),
      FlagSpecification(
        key: "useCaseFile",
        name: "--use-case-file",
        kind: .string,
        summary: "Read the use-case JSON from a file (alternative to --use-case-json).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "expectedHash",
        name: "--expected-hash",
        kind: .string,
        summary: "Optimistic-concurrency guard for updates.",
        valueName: "<hash>",
      ),
    ],
    subrow: "4b",
  )

  static let remove = CommandSpecification(
    unportedPath: ["matrix", "remove"],
    command: "matrix.remove",
    summary: "Soft-remove a use-case row.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      FlagSpecification(
        key: "useCase",
        name: "--use-case",
        kind: .string,
        summary: "Use-case id to remove.",
        valueName: "<id>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: "Why the row is being removed.",
        valueName: "<text>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "expectedHash",
        name: "--expected-hash",
        kind: .string,
        summary: "Optimistic-concurrency guard.",
        valueName: "<hash>",
      ),
      CommonFlags.json,
    ],
    subrow: "4b",
  )
}
