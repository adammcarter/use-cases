/// The `recover` commands, declared for help and flag checking. Their port is
/// ladder row 4c; until it lands each one refuses with `cli_not_yet_ported`.
enum RecoverCommands {
  static let all = [
    recover,
  ]

  static let recover = CommandSpecification(
    unportedPath: ["recover"],
    command: "markers.recover",
    summary: "Drive a drifted / unproven row back to green: re-verify (and optionally "
      + "re-prove), then report.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      FlagSpecification(
        key: "productRoot",
        name: "--product-root",
        kind: .string,
        summary: "Root to scope markers/verifiers to (default --repo).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "bindings",
        name: "--bindings",
        kind: .string,
        summary: "Override the bindings ledger path (default "
          + "<data-root>/.use-cases/bindings.jsonl).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "proofs",
        name: "--proofs",
        kind: .string,
        summary: "Override the proof ledger path (default "
          + "<data-root>/.use-cases/proofs.jsonl).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "row",
        name: "--row",
        kind: .string,
        summary: "Target row id.",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "all",
        name: "--all",
        kind: .boolean,
        summary: "Target every bound row.",
      ),
      FlagSpecification(
        key: "signingKeyEnv",
        name: "--signing-key-env",
        kind: .string,
        summary: "Env var holding the signing key (CI secret) — ALSO re-prove the "
          + "row(s) to FRESH.",
        valueName: "<name>",
      ),
      FlagSpecification(
        key: "keyId",
        name: "--key-id",
        kind: .string,
        summary: "Signing key id (default trusted-ci).",
        valueName: "<id>",
      ),
      FlagSpecification(
        key: "publicKey",
        name: "--public-key",
        kind: .string,
        summary: "Trusted public key to verify proof signatures (needed for "
          + "--signing-key-env to read FRESH).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "keyring",
        name: "--keyring",
        kind: .string,
        summary: "Multi-key public-key registry (alternative to --public-key).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "generatedAt",
        name: "--generated-at",
        kind: .string,
        summary: "Override the generated-at timestamp.",
        valueName: "<iso>",
      ),
      FlagSpecification(
        key: "baseRef",
        name: "--base-ref",
        kind: .string,
        summary: "Diff base for the append-only check.",
        valueName: "<ref>",
      ),
    ],
    subrow: "4c",
  )
}
