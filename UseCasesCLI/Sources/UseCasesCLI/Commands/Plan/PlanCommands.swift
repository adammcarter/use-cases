/// The plan commands, declared for help and flag checking. Their port is
/// ladder row 4e; until it lands each one refuses with `cli_not_yet_ported`.
enum PlanCommands {
  static let all = [
    showcase,
    walkthrough,
    cards,
  ]

  static let showcase = CommandSpecification(
    unportedPath: ["plan", "showcase"],
    command: "plan.showcase",
    summary: "Select a showcase presentation plan.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      PlanFlags.audience,
      PlanFlags.timebox,
      PlanFlags.maxItems,
      PlanFlags.host,
      PlanFlags.changedPath,
      PlanFlags.generatedAt,
      PlanFlags.strict,
    ],
    subrow: "4e",
  )

  static let walkthrough = CommandSpecification(
    unportedPath: ["plan", "walkthrough"],
    command: "plan.walkthrough",
    summary: "Select a walkthrough presentation plan.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      PlanFlags.audience,
      PlanFlags.timebox,
      PlanFlags.maxItems,
      PlanFlags.host,
      PlanFlags.changedPath,
      PlanFlags.generatedAt,
      PlanFlags.strict,
    ],
    subrow: "4e",
  )

  static let cards = CommandSpecification(
    unportedPath: ["plan", "cards"],
    command: "plan.cards",
    summary: "Render presentation cards from a saved plan file.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      FlagSpecification(
        key: "planFile",
        name: "--plan-file",
        kind: .string,
        summary: "Saved presentation plan file (inside the workspace).",
        valueName: "<path>",
        isRequired: true,
      ),
      CommonFlags.json,
    ],
    subrow: "4e",
  )
}
