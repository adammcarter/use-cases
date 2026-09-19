/// Flags more than one plan command declares, defined once.
enum PlanFlags {
  static let audience = FlagSpecification(
    key: "audience",
    name: "--audience",
    kind: .string,
    summary: "Audience role for the plan (default reviewer).",
    valueName: "<role>",
  )

  static let timebox = FlagSpecification(
    key: "timebox",
    name: "--timebox",
    kind: .integer,
    summary: "Timebox budget in seconds.",
    valueName: "<seconds>",
  )

  static let maxItems = FlagSpecification(
    key: "maxItems",
    name: "--max-items",
    kind: .integer,
    summary: "Cap the number of selected items.",
    valueName: "<n>",
  )

  static let host = FlagSpecification(
    key: "host",
    name: "--host",
    kind: .string,
    summary: "Host surface to plan for (default unknown).",
    valueName: "<surface>",
  )

  static let changedPath = FlagSpecification(
    key: "changedPath",
    name: "--changed-path",
    kind: .string,
    summary: "Bias selection toward changed paths (repeatable).",
    valueName: "<path>",
    isRepeatable: true,
  )

  static let generatedAt = FlagSpecification(
    key: "generatedAt",
    name: "--generated-at",
    kind: .string,
    summary: "Override the generated-at timestamp.",
    valueName: "<iso>",
  )

  static let strict = FlagSpecification(
    key: "strict",
    name: "--strict",
    kind: .boolean,
    summary: "Fail when the matrix/evidence is incomplete.",
  )

  static let planFile = FlagSpecification(
    key: "planFile",
    name: "--plan-file",
    kind: .string,
    summary: "Saved presentation plan file (inside the workspace).",
    valueName: "<path>",
    isRequired: true,
  )
}
