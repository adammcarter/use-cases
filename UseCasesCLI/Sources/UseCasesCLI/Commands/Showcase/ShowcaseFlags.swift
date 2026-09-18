/// Flags more than one showcase command declares, defined once.
enum ShowcaseFlags {
  static let idempotencyKey = FlagSpecification(
    key: "idempotencyKey",
    name: "--idempotency-key",
    kind: .string,
    summary: "Idempotency key (defaults to a derived cli: key).",
    valueName: "<key>",
  )

  static let run = FlagSpecification(
    key: "run",
    name: "--run",
    kind: .string,
    summary: "Showcase run id.",
    valueName: "<id>",
    isRequired: true,
  )

  static let item = FlagSpecification(
    key: "item",
    name: "--item",
    kind: .string,
    summary: "Plan item id.",
    valueName: "<id>",
    isRequired: true,
  )

  static let actor = FlagSpecification(
    key: "actor",
    name: "--actor",
    kind: .string,
    summary: "Actor type (defaults to agent).",
    valueName: "<type>",
  )

  static let approvalToken = FlagSpecification(
    key: "approvalToken",
    name: "--approval-token",
    kind: .string,
    summary: "Signed approval token JSON from `use-cases approve-run` — the ONLY trusted human "
      + "sign-off path (F3).",
    valueName: "<path>",
  )

  static let keyring = FlagSpecification(
    key: "keyring",
    name: "--keyring",
    kind: .string,
    summary: "Public-key keyring that verifies --approval-token, or narrows pinned "
      + "approval_trust.",
    valueName: "<path>",
  )

  static let publicKey = FlagSpecification(
    key: "publicKey",
    name: "--public-key",
    kind: .string,
    summary: "Single public key that verifies --approval-token, or narrows pinned "
      + "approval_trust.",
    valueName: "<path>",
  )
}
