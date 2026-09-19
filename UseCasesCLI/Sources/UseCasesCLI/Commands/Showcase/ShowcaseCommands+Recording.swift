/// The showcase verbs that append to a run's ledger: start, the two
/// recordings, the failure decision, pause, resume and finish.
extension ShowcaseCommands {
  static let start = CommandSpecification(
    path: ["showcase", "start"],
    command: "showcase.start",
    summary: "Start a showcase run from a plan file or an ad hoc selection.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      FlagSpecification(
        key: "planFile",
        name: "--plan-file",
        kind: .string,
        summary: "Plan file to start the run from (inside the workspace).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "adhoc",
        name: "--adhoc",
        kind: .boolean,
        summary: "Build an ad hoc plan instead of reading --plan-file.",
      ),
      FlagSpecification(
        key: "select",
        name: "--select",
        kind: .string,
        summary: "Use-case id to select for the ad hoc plan.",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "audience",
        name: "--audience",
        kind: .string,
        summary: "Ad hoc plan audience (defaults to reviewer).",
        valueName: "<audience>",
      ),
      FlagSpecification(
        key: "timebox",
        name: "--timebox",
        kind: .integer,
        summary: "Ad hoc plan timebox in seconds (defaults to 600).",
        valueName: "<seconds>",
      ),
      FlagSpecification(
        key: "generatedAt",
        name: "--generated-at",
        kind: .string,
        summary: "Ad hoc plan generation timestamp.",
        valueName: "<iso>",
      ),
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the start event.",
        valueName: "<iso>",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runStart(context)
  }

  static let recordObservation = CommandSpecification(
    path: ["showcase", "record-observation"],
    command: "showcase.record-observation",
    summary: "Append an observation to a showcase run plan item.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      ShowcaseFlags.item,
      FlagSpecification(
        key: "text",
        name: "--text",
        kind: .string,
        summary: "Observation text.",
        valueName: "<text>",
        isRequired: true,
      ),
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the observation event.",
        valueName: "<iso>",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runRecordObservation(context)
  }

  static let recordVerdict = CommandSpecification(
    path: ["showcase", "record-verdict"],
    command: "showcase.record-verdict",
    summary: "Append a verdict to a showcase run plan item.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      ShowcaseFlags.item,
      FlagSpecification(
        key: "verdict",
        name: "--verdict",
        kind: .string,
        summary: "Verdict value.",
        valueName: "<verdict>",
        isRequired: true,
      ),
      ShowcaseFlags.actor,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the verdict event.",
        valueName: "<iso>",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runRecordVerdict(context)
  }

  static let decide = CommandSpecification(
    path: ["showcase", "decide"],
    command: "showcase.decide",
    summary: "Record a failure decision against a showcase verdict event.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      FlagSpecification(
        key: "verdictEvent",
        name: "--verdict-event",
        kind: .string,
        summary: "Verdict event id the decision targets.",
        valueName: "<event-id>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "decision",
        name: "--decision",
        kind: .string,
        summary: "Decision value.",
        valueName: "<decision>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: "Why the decision was made.",
        valueName: "<text>",
        isRequired: true,
      ),
      ShowcaseFlags.actor,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the decision event.",
        valueName: "<iso>",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runDecide(context)
  }

  static let pause = CommandSpecification(
    path: ["showcase", "pause"],
    command: "showcase.pause",
    summary: "Pause a showcase run.",
    flags: transitionFlags(
      reasonSummary: "Pause reason (defaults to 'Paused by operator.').",
      eventName: "pause",
    ),
  ) { context throws(CommandFailure) in
    try runPause(context)
  }

  static let resume = CommandSpecification(
    path: ["showcase", "resume"],
    command: "showcase.resume",
    summary: "Resume a paused showcase run.",
    flags: transitionFlags(
      reasonSummary: "Resume reason (defaults to 'Resumed by operator.').",
      eventName: "resume",
    ),
  ) { context throws(CommandFailure) in
    try runResume(context)
  }

  static let finish = CommandSpecification(
    path: ["showcase", "finish"],
    command: "showcase.finish",
    summary: "Finish a showcase run.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the finish event.",
        valueName: "<iso>",
      ),
    ],
  ) { context throws(CommandFailure) in
    try runFinish(context)
  }

  /// Pause and resume declare the same flags, worded for the verb.
  private static func transitionFlags(
    reasonSummary: String,
    eventName: String,
  ) -> [FlagSpecification] {
    [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: reasonSummary,
        valueName: "<text>",
      ),
      ShowcaseFlags.actor,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the \(eventName) event.",
        valueName: "<iso>",
      ),
    ]
  }
}
