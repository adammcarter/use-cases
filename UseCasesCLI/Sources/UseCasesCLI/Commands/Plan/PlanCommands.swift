/// `plan showcase|walkthrough|cards` (packages/cli/src/commands/plan.ts).
///
/// Selection is in `PlanCommands+Selection.swift` and the cards in
/// `PlanCommands+Cards.swift`, which reads a saved plan file through
/// ``PlanCardItem``.
enum PlanCommands {
  static let all = [
    showcase,
    walkthrough,
    cards,
  ]

  static let showcase = CommandSpecification(
    path: ["plan", "showcase"],
    command: "plan.showcase",
    summary: "Select a showcase presentation plan.",
    flags: selectionFlags,
  ) { context throws(CommandFailure) in
    try runSelection(context, mode: .showcase)
  }

  static let walkthrough = CommandSpecification(
    path: ["plan", "walkthrough"],
    command: "plan.walkthrough",
    summary: "Select a walkthrough presentation plan.",
    flags: selectionFlags,
  ) { context throws(CommandFailure) in
    try runSelection(context, mode: .walkthrough)
  }

  static let cards = CommandSpecification(
    path: ["plan", "cards"],
    command: "plan.cards",
    summary: "Render presentation cards from a saved plan file.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      PlanFlags.planFile,
      CommonFlags.json,
    ],
  ) { context throws(CommandFailure) in
    try runCards(context)
  }

  /// Both selection commands declare the same flags.
  static let selectionFlags = [
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
  ]
}
