/// The `approve-run` commands, declared for help and flag checking. Their port is
/// ladder row 4e; until it lands each one refuses with `cli_not_yet_ported`.
enum ApproveRunCommands {
  static let all = [
    approveRun,
  ]

  static let approveRun = CommandSpecification(
    unportedPath: ["approve-run"],
    command: "showcase.approve_run",
    summary: "Sign a plugin-minted approval request out-of-band (human, own shell, "
      + "out-of-scope key).",
    flags: [
      FlagSpecification(
        key: "request",
        name: "--request",
        kind: .string,
        summary: "Path to the plugin-minted ApprovalRequest JSON.",
        valueName: "<file>",
        isRequired: true,
      ),
      FlagSpecification(
        key: "keyFile",
        name: "--key-file",
        kind: .string,
        summary: "ed25519 private key PEM, OUTSIDE the agent's scope (0600 user-owned).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "keyEnv",
        name: "--key-env",
        kind: .string,
        summary: "Env var holding the ed25519 private key PEM (alternative to --key-file).",
        valueName: "<VAR>",
      ),
      FlagSpecification(
        key: "keyId",
        name: "--key-id",
        kind: .string,
        summary: "Keyring key_id the plugin verifies the ed25519 token against.",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "webauthnAssertion",
        name: "--webauthn-assertion",
        kind: .string,
        summary: "JSON WebAuthn assertion from the operator's platform authenticator; "
          + "ceremony is out of scope, verification happens against pinned "
          + "approval_trust.",
        valueName: "<file>",
      ),
      FlagSpecification(
        key: "decision",
        name: "--decision",
        kind: .string,
        summary: "approved | approved_with_known_gaps | rejected (default approved).",
        valueName: "<decision>",
      ),
      FlagSpecification(
        key: "assuranceMethod",
        name: "--assurance-method",
        kind: .string,
        summary: "ed25519: automation | same_channel | os_presence (default "
          + "os_presence). WebAuthn assertions record webauthn.",
        valueName: "<method>",
      ),
      FlagSpecification(
        key: "out",
        name: "--out",
        kind: .string,
        summary: "Write the token to <file> instead of printing it inline.",
        valueName: "<file>",
      ),
      FlagSpecification(
        key: "json",
        name: "--json",
        kind: .boolean,
        summary: "Emit the machine-readable JSON result envelope.",
      ),
    ],
    subrow: "4e",
  )
}
