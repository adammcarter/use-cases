extension ShowcaseCommands {
  static let status = CommandSpecification(
    unportedPath: ["showcase", "status"],
    command: "showcase.status",
    summary: "Replay and report a showcase run's status.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      FlagSpecification(
        key: "keyring",
        name: "--keyring",
        kind: .string,
        summary: "Keyring to verify an embedded approval token, or narrow pinned "
          + "approval_trust.",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "publicKey",
        name: "--public-key",
        kind: .string,
        summary: "Single public key to verify an embedded approval token, or narrow "
          + "pinned approval_trust.",
        valueName: "<path>",
      ),
    ],
    subrow: "4e",
  )

  static let requestApproval = CommandSpecification(
    unportedPath: ["showcase", "request-approval"],
    command: "showcase.request-approval",
    summary: "Mint an unsigned approval request for a finished showcase run.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
    ],
    subrow: "4e",
  )

  static let approve = CommandSpecification(
    unportedPath: ["showcase", "approve"],
    command: "showcase.approve",
    summary: "Record an approval for a showcase run.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      FlagSpecification(
        key: "statement",
        name: "--statement",
        kind: .string,
        summary: "Approval statement.",
        valueName: "<text>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "actor",
        name: "--actor",
        kind: .string,
        summary: "Actor type (defaults to agent; --approval-token forces user).",
        valueName: "<type>",
      ),
      ShowcaseFlags.approvalToken,
      ShowcaseFlags.keyring,
      ShowcaseFlags.publicKey,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the approval event.",
        valueName: "<iso>",
      ),
    ],
    subrow: "4e",
  )

  static let reject = CommandSpecification(
    unportedPath: ["showcase", "reject"],
    command: "showcase.reject",
    summary: "Record a rejection for a showcase run.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      FlagSpecification(
        key: "statement",
        name: "--statement",
        kind: .string,
        summary: "Rejection statement.",
        valueName: "<text>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "actor",
        name: "--actor",
        kind: .string,
        summary: "Actor type (defaults to user).",
        valueName: "<type>",
      ),
      ShowcaseFlags.approvalToken,
      ShowcaseFlags.keyring,
      ShowcaseFlags.publicKey,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the rejection event.",
        valueName: "<iso>",
      ),
    ],
    subrow: "4e",
  )

  static let correct = CommandSpecification(
    unportedPath: ["showcase", "correct"],
    command: "showcase.correct",
    summary: "Correct a previously recorded showcase verdict.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      ShowcaseFlags.run,
      FlagSpecification(
        key: "targetEvent",
        name: "--target-event",
        kind: .string,
        summary: "Verdict event id to correct.",
        valueName: "<event-id>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "verdict",
        name: "--verdict",
        kind: .string,
        summary: "Corrected verdict value.",
        valueName: "<verdict>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "reason",
        name: "--reason",
        kind: .string,
        summary: "Why the verdict is being corrected.",
        valueName: "<text>",
        isRequired: true,
      ),
      ShowcaseFlags.actor,
      ShowcaseFlags.idempotencyKey,
      FlagSpecification(
        key: "recordedAt",
        name: "--recorded-at",
        kind: .string,
        summary: "Recorded-at timestamp for the correction event.",
        valueName: "<iso>",
      ),
    ],
    subrow: "4e",
  )
}
