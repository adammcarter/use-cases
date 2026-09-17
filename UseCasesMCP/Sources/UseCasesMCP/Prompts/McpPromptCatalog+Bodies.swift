// swiftlint:disable line_length
// The prompt bodies are verbatim product text (packages/mcp/src/prompts.ts):
// every line is one paragraph or one example command, reproduced exactly, so a
// line is as long as the sentence is. Wrapping them would only hide the
// comparison the corpus makes.
/// The four prompt bodies, word for word.
///
/// Every command and flag named here is a real one; a prompt that invented a
/// flag would send an agent down a path the CLI refuses.
extension McpPromptCatalog {
  static func adoptRepo(_ repository: String) -> McpPromptResult {
    McpPromptResult(
      description: "Step-by-step adoption of the use-case matrix — keyless daily loop first, "
        + "signing opt-in.",
      text: [
        "Goal: adopt Use Cases in this repository so every shippable behaviour is a matrix row bound to code and confirmed still-covered by the KEYLESS daily loop — no keys, no CI. Signing is an opt-in upgrade you add later, only when you want a cryptographic release gate.",
        "",
        "Fastest start: `uc init --repo \(repository)` scaffolds the workspace (a use-cases.yml config + a use-cases/ directory with one example row). To adopt by hand instead — e.g. onto an existing repo — author the same two things:",
        "1. A workspace config `use-cases.yml` at the repo root (declares data_root, use_cases_dir, component_id, and optional verifiers/release_gate).",
        "2. A `use-cases/` directory of use-case YAML files, one row per behaviour.",
        "",
        "THE KEYLESS DAILY LOOP — no keys, no CI:",
        "- Validate the matrix:    uc matrix validate --repo \(repository) --json",
        "- List/inspect rows:      uc matrix list --repo \(repository) --json",
        "- Bind a row to code:     uc bind --repo \(repository) --row <row-id> --file <path> --mode explicit --start-line <n> --end-line <m> --json",
        "                          (or --mode swift-func --line <n> for a Swift function body)",
        "- Verify locally:         uc verify --repo \(repository) --all --json",
        "                          (with no --out this writes the UNSIGNED results ledger to <data-root>/.use-cases/verification-results.jsonl, which scan auto-discovers)",
        "- Scan freshness:         uc scan --repo \(repository) --json",
        "                          each verified row reports local_status: VERIFIED_LOCAL (status stays UNPROVEN — that is a healthy keyless row). `uc scan --gate` exits non-zero if a required row is below the bar (>= VERIFIED_LOCAL by default).",
        "",
        "OPT-IN UPGRADE — signed proofs (FRESH) for a release/audit gate, in trusted CI only:",
        "- Generate a keypair:     uc keygen --out <dir-outside-repo> --ci github   (private key is a CI secret — never in the repo)",
        "- Mint proofs (CI):       uc prove --repo \(repository) --all --verification-results <results> --append --trusted-ci --signing-key-env <ENV> --json",
        "- Gate the ledger:        uc validate-ledger --repo \(repository) --json",
        "- Release gate:           uc scan --repo \(repository) --policy-mode release --gate --json",
        "",
        "`prove` mints signed proofs and must run only in trusted CI; it is intentionally not exposed over MCP. Everyday agent work stays keyless. Use the read-only MCP resources (uc://matrix, uc://freshness, uc://ledger, uc://bindings) to inspect state at any point.",
      ].joined(separator: "\n"),
    )
  }

  static func bindRow(
    _ repository: String,
    _ row: String,
    _ file: String,
  ) -> McpPromptResult {
    McpPromptResult(
      description: "Bind row \(row) to its implementation and take it to VERIFIED_LOCAL.",
      text: [
        "Goal: bind matrix row `\(row)` to the code that implements it and confirm it is green the keyless way — bind -> verify -> VERIFIED_LOCAL, with no keys and no CI.",
        "",
        "1. Confirm the row exists in the matrix:",
        "   uc matrix list --repo \(repository) --json   (look for \(row))",
        "",
        "2. Place a binding marker in the source and register it. For an explicit line span (--mode explicit REQUIRES both --start-line and --end-line):",
        "   uc bind --repo \(repository) --row \(row) --file \(file) --mode explicit --start-line <n> --end-line <m> --json",
        "   For a Swift function body (span inferred from the function line):",
        "   uc bind --repo \(repository) --row \(row) --file \(file) --mode swift-func --line <n> --json",
        "   Add --suffix <name> to register more than one binding slug for the same row; add --register-existing to register a marker already present in the source.",
        "",
        "3. Run the row's verifier (with no --out this writes the UNSIGNED results ledger scan auto-discovers):",
        "   uc verify --repo \(repository) --row \(row) --json",
        "",
        "4. Confirm the keyless green:",
        "   uc scan --repo \(repository) --json",
        "   The row should report local_status: VERIFIED_LOCAL (status stays UNPROVEN — a healthy keyless row: a binding + a passing local verify, no signed proof yet).",
        "",
        "Binding only edits source + the append-only registry, and verify only writes an UNSIGNED local ledger. Neither mints a proof — signing to FRESH is the opt-in upgrade that runs in trusted CI (`uc prove`), which is not available over MCP.",
      ].joined(separator: "\n"),
    )
  }

  static func recoverRow(
    _ repository: String,
    _ row: String,
  ) -> McpPromptResult {
    McpPromptResult(
      description: "Recover row \(row) back to green (VERIFIED_LOCAL keyless-first; FRESH "
        + "opt-in).",
      text: [
        "Goal: get row `\(row)` back to green. Keyless-first: the everyday target is local_status: VERIFIED_LOCAL (no keys, no CI). Re-proving to signed FRESH is the opt-in upgrade for a release/audit gate.",
        "",
        "Why a row drifts off green:",
        "- STALE_LOCAL (keyless): a local verify result exists but the bound code or the test has changed since — the keyless analogue of SUSPECT.",
        "- UNVERIFIED_LOCAL: the row is bound but has never been verified locally.",
        "- SUSPECT / UNPROVEN (signed tier): a signed proof is stale (code/binding/verifier changed) or absent.",
        "",
        "1. Inspect the current state and the exact reason:",
        "   uc scan --repo \(repository) --json   (read rows[].status, rows[].local_status and rows[].reasons for \(row))",
        "",
        "2. If the binding moved (code edited/relocated), re-bind so the marker tracks the new span:",
        "   uc bind --repo \(repository) --row \(row) --file <path> --mode explicit --start-line <n> --end-line <m> --json",
        "",
        "3. Recover in one command — re-verify and report the new state:",
        "   uc recover --repo \(repository) --row \(row) --json",
        "   This re-runs the row's verifier (the same run as `uc verify`), writes the unsigned results ledger, re-scans, and reports the resulting local_status/status. The row returns to VERIFIED_LOCAL. `uc recover` NEVER fakes green: if the verifier genuinely fails it exits non-zero and names the failing row — fix the code or the test, then re-run.",
        "   To inspect a raw verifier run on its own, use `uc verify --repo \(repository) --row \(row) --json`.",
        "",
        "4. OPT-IN — also re-prove to signed FRESH (release/audit only, trusted CI):",
        "   uc recover --repo \(repository) --row \(row) --signing-key-env UCM_CI_SIGNING_KEY --public-key <path> --json",
        "   Supplying --signing-key-env additionally mints a signed proof (trusted-CI). Signing runs only in trusted CI and is intentionally not exposed over MCP; do not attempt to sign from an ordinary agent session.",
        "",
        "5. Confirm the row is green again:",
        "   uc scan --repo \(repository) --json   (expect local_status: VERIFIED_LOCAL, or status: FRESH if you re-proved)",
        "   uc validate-ledger --repo \(repository) --json   (signed tier only)",
      ].joined(separator: "\n"),
    )
  }

  static func releaseReview(_ repository: String) -> McpPromptResult {
    McpPromptResult(
      description: "Release gate review for required_for_release rows.",
      text: [
        "Goal: confirm the matrix is release-ready — every row marked required_for_release is FRESH and the proof ledger is intact.",
        "",
        "1. Run the release-mode scan with the gate (release policy blocks any required row that is not FRESH, and any INVALID row; --gate turns that into a non-zero exit for CI):",
        "   uc scan --repo \(repository) --policy-mode release --gate --json",
        "   Read guard_ok plus rows[]: every row with required_for_release=true must have status FRESH and policy_block=false. (Outside release, the gate bar is >= VERIFIED_LOCAL — the keyless green.)",
        "",
        "2. Cross-check matrix + evidence health:",
        "   uc matrix status --repo \(repository) --json",
        "",
        "3. Validate ledger/registry integrity (append-only discipline, signatures, hash chain):",
        "   uc validate-ledger --repo \(repository) --json",
        "",
        "If any required row is SUSPECT/UNPROVEN/UNBOUND/INVALID, recover it (see the uc/recover-suspect-row prompt) before releasing.",
        "These are read-only checks — you can also inspect uc://freshness, uc://ledger, and uc://matrix/status over MCP without running anything.",
      ].joined(separator: "\n"),
    )
  }
}

// swiftlint:enable line_length
