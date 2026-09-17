/// Flags more than one marker command declares, defined once.
enum MarkersFlags {
  static let productRoot = FlagSpecification(
    key: "productRoot",
    name: "--product-root",
    kind: .string,
    summary: "Root to scope markers/verifiers to (default --repo).",
    valueName: "<path>",
  )

  static let bindings = FlagSpecification(
    key: "bindings",
    name: "--bindings",
    kind: .string,
    summary: "Override the bindings ledger path (default "
      + "<data-root>/.use-cases/bindings.jsonl).",
    valueName: "<path>",
  )

  static let proofs = FlagSpecification(
    key: "proofs",
    name: "--proofs",
    kind: .string,
    summary: "Override the proof ledger path (default "
      + "<data-root>/.use-cases/proofs.jsonl).",
    valueName: "<path>",
  )

  static let mode = FlagSpecification(
    key: "mode",
    name: "--mode",
    kind: .string,
    summary: "explicit | swift-func.",
    valueName: "<mode>",
  )

  static let startLine = FlagSpecification(
    key: "startLine",
    name: "--start-line",
    kind: .integer,
    summary: "Span start line (REQUIRED for --mode explicit).",
    valueName: "<n>",
  )

  static let endLine = FlagSpecification(
    key: "endLine",
    name: "--end-line",
    kind: .integer,
    summary: "Span end line (REQUIRED for --mode explicit).",
    valueName: "<n>",
  )

  static let commentPrefix = FlagSpecification(
    key: "commentPrefix",
    name: "--comment-prefix",
    kind: .string,
    summary: "Override the line-comment prefix (else inferred from extension/shebang).",
    valueName: "<s>",
  )

  static let publicKey = FlagSpecification(
    key: "publicKey",
    name: "--public-key",
    kind: .string,
    summary: "Trusted public key to verify proof signatures (else proofs read UNPROVEN).",
    valueName: "<path>",
  )

  static let keyring = FlagSpecification(
    key: "keyring",
    name: "--keyring",
    kind: .string,
    summary: "Multi-key public-key registry (alternative to --public-key).",
    valueName: "<path>",
  )

  static let generatedAt = FlagSpecification(
    key: "generatedAt",
    name: "--generated-at",
    kind: .string,
    summary: "Override the generated-at timestamp.",
    valueName: "<iso>",
  )

  static let baseRef = FlagSpecification(
    key: "baseRef",
    name: "--base-ref",
    kind: .string,
    summary: "Diff base for the append-only check.",
    valueName: "<ref>",
  )

  static let row = FlagSpecification(
    key: "row",
    name: "--row",
    kind: .string,
    summary: "Target row id.",
    valueName: "<id>",
  )

  static let all = FlagSpecification(
    key: "all",
    name: "--all",
    kind: .boolean,
    summary: "Target every bound row.",
  )
}
