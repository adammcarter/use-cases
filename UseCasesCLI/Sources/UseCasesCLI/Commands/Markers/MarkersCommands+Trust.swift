extension MarkersCommands {
  static let scan = CommandSpecification(
    unportedPath: ["scan"],
    command: "markers.scan",
    summary: "Scan code markers against the bindings ledger and report freshness.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      FlagSpecification(
        key: "policyMode",
        name: "--policy-mode",
        kind: .string,
        summary: "feature | release | custom.",
        valueName: "<mode>",
      ),
      FlagSpecification(
        key: "gate",
        name: "--gate",
        kind: .boolean,
        summary: "Exit 1 when a row marked `approval_policy.required_for_release: true` "
          + "is below the bar (release => FRESH, else >= VERIFIED_LOCAL). ONLY "
          + "required rows are enforced; non-required drift is reported as a "
          + "warning, not a block. Off by default.",
      ),
      FlagSpecification(
        key: "results",
        name: "--results",
        kind: .string,
        summary: "Override the unsigned verify-results ledger feeding the keyless tier "
          + "(default <data-root>/.use-cases/verification-results.jsonl).",
        valueName: "<path>",
      ),
      MarkersFlags.publicKey,
      MarkersFlags.keyring,
      MarkersFlags.generatedAt,
      MarkersFlags.baseRef,
      FlagSpecification(
        key: "ci",
        name: "--ci",
        kind: .boolean,
        summary: "CI mode (print inferred spans).",
      ),
    ],
    subrow: "4c",
  )

  static let impact = CommandSpecification(
    unportedPath: ["impact"],
    command: "markers.impact",
    summary: "Show which bound behaviours a git change touches (advisory; re-verify the "
      + "impacted ones).",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      MarkersFlags.publicKey,
      MarkersFlags.keyring,
      FlagSpecification(
        key: "base",
        name: "--base",
        kind: .string,
        summary: "Compare the working tree against this ref instead of HEAD.",
        valueName: "<ref>",
      ),
      FlagSpecification(
        key: "staged",
        name: "--staged",
        kind: .boolean,
        summary: "Compare the staged index against HEAD instead of the working tree.",
      ),
      MarkersFlags.generatedAt,
    ],
    subrow: "4c",
  )

  static let prove = CommandSpecification(
    unportedPath: ["prove"],
    command: "markers.prove",
    summary: "Mint SIGNED proofs from verification results (CI-only signing key).",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      MarkersFlags.row,
      MarkersFlags.all,
      FlagSpecification(
        key: "verificationResults",
        name: "--verification-results",
        kind: .string,
        summary: "The results file written by `verify --out` (REQUIRED).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "trustedCi",
        name: "--trusted-ci",
        kind: .boolean,
        summary: "Mint as the trusted CI prover.",
      ),
      FlagSpecification(
        key: "signingKeyEnv",
        name: "--signing-key-env",
        kind: .string,
        summary: "Env var holding the signing key (CI secret).",
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
        key: "authorityFile",
        name: "--authority-file",
        kind: .string,
        summary: "Explicit CI authority record (JSON).",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "append",
        name: "--append",
        kind: .boolean,
        summary: "Append minted proofs to the evidence ledger.",
      ),
      FlagSpecification(
        key: "refresh",
        name: "--refresh",
        kind: .boolean,
        summary: "Re-mint proofs for rows whose context changed.",
      ),
      FlagSpecification(
        key: "dryRun",
        name: "--dry-run",
        kind: .boolean,
        summary: "Preview without writing the evidence ledger.",
      ),
      FlagSpecification(
        key: "unsafeAssumeVerificationResult",
        name: "--unsafe-assume-verification-result",
        kind: .string,
        summary: "DANGEROUS: assume the row's verification passed (honoured only with "
          + "UCM_ALLOW_UNSAFE_VERIFICATION=1).",
        valueName: "<result>",
      ),
      MarkersFlags.publicKey,
      MarkersFlags.keyring,
      MarkersFlags.generatedAt,
      MarkersFlags.baseRef,
    ],
    subrow: "4c",
  )

  static let verify = CommandSpecification(
    unportedPath: ["verify"],
    command: "markers.verify",
    summary: "Run each bound row's verifier and write an UNSIGNED results ledger.",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      MarkersFlags.row,
      MarkersFlags.all,
      FlagSpecification(
        key: "out",
        name: "--out",
        kind: .string,
        summary: "Write the unsigned results ledger (feed this to `prove "
          + "--verification-results`). Keep it OUTSIDE the evidence dir.",
        valueName: "<path>",
      ),
      FlagSpecification(
        key: "dryRun",
        name: "--dry-run",
        kind: .boolean,
        summary: "Show which verifiers WOULD run for the targeted rows. Runs nothing, "
          + "writes nothing.",
      ),
      MarkersFlags.publicKey,
      MarkersFlags.keyring,
      MarkersFlags.generatedAt,
      MarkersFlags.baseRef,
    ],
    subrow: "4c",
  )

  static let validateLedger = CommandSpecification(
    unportedPath: ["validate-ledger"],
    command: "markers.validate-ledger",
    summary: "Validate the marker evidence ledger (append-only, signatures, schema).",
    flags: [
      CommonFlags.repository,
      CommonFlags.dataRoot,
      CommonFlags.component,
      CommonFlags.json,
      MarkersFlags.productRoot,
      MarkersFlags.bindings,
      MarkersFlags.proofs,
      MarkersFlags.publicKey,
      MarkersFlags.keyring,
      MarkersFlags.baseRef,
    ],
    subrow: "4c",
  )
}
