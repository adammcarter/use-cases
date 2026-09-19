import Foundation

/// Holds the matrix to the conventions in `docs/rewrite/scenario-conventions.md`.
///
/// This is the Swift port of `scripts/check-scenario-conventions.mjs`, the last
/// JavaScript tool in the repository. The script was deleted in the 0.8.0
/// clean-up rather than kept, and porting it rather than dropping it was the
/// point: nothing ever ran it automatically, so the convention the document
/// describes was decoration. As a test it is run by `swift test` like
/// everything else, and a feature file that drifts fails the suite.
///
/// **The port is deliberately a transliteration.** The `.mjs` read the matrix
/// with a small line reader rather than a YAML parser, and so does this — same
/// indentation rules, same patterns, same order of checks. A "better" reader
/// would answer a different question, and the one thing that had to be true of
/// this port is that it finds exactly what the script found. Measured
/// 2026-09-18 against the live `use-cases/` tree: 34 findings, identical
/// strings, identical when sorted.
///
/// There is no `@use-case:` marker on this file. It proves no row: it holds a
/// DOCUMENT's rules over the matrix, and inventing a row for it would be new
/// behaviour, which ADR 0007 says stops for the owner.
enum ScenarioConventions {
  /// `agent` and `user` are verifier KINDS, not ids a `verifiers:` block
  /// defines — an agent observation or a person's sign-off has no command
  /// behind it by design. Counting them as dangling would bury the rows that
  /// really do name a `script` verifier nobody wrote, which is a bug rather
  /// than a decision.
  static let builtInVerifiers: Set<String> = ["agent", "user"]

  /// The matrix root, relative to the repository, exactly as the script had it.
  static let matrixDirectory = "use-cases"

  // MARK: - The eight rows the conventions document itself exempts

  /// `docs/rewrite/scenario-conventions.md` §6 and §8a name eight active rows
  /// that CANNOT satisfy the scenario convention, and say why: they describe
  /// how an agent must behave, or they end in a person's judgement, so there is
  /// no command whose JSON a golden/bad/edge scenario could be asserted
  /// against. §8a records that whether they are parked like the `roadmap.*`
  /// rows or covered by a named exception to ADR 0007 decision 2 was
  /// deliberately left for the owner to settle at the end of the ladder.
  ///
  /// They are pinned here by ROW ID rather than by their 32 finding strings so
  /// that settling §8a is one edit in one place. Pinning them is not a
  /// weakening of the check: every other active row is held to zero findings,
  /// a ninth row joining them fails the suite, and
  /// ``theDocumentedExemptionsAreStillEarned`` fails if one of the eight stops
  /// needing the exemption.
  ///
  /// What was NOT done, and deliberately: tagging these rows `no-bad-path` /
  /// `no-edge-path` or renaming their scenarios `golden_*` would make the check
  /// green by editing the matrix. It moves eight `semantic_hash`es, stales the
  /// evidence taken against them, and answers the owner's open question by
  /// sleight of hand.
  static let doctrineRows: [String: String] = [
    "lifecycle.loop.continuous_loop":
      "§8a doctrine: how an agent should run the loop; no command implements it.",
    "lifecycle.loop.workflow_modes":
      "§8a doctrine: when an agent alternates modes; no command implements it.",
    "lifecycle.loop.agent_matrix_stewardship":
      "§8a doctrine: how an agent keeps the matrix true; no command implements it.",
    "lifecycle.loop.user_feature_printout":
      "§8a doctrine: when an agent asks the user; no command implements it.",
    "lifecycle.loop.opt_out_or_tiny_change":
      "§8a doctrine: when an agent may skip the loop; no command implements it.",
    "evidence.ledger.untrusted_content_boundary":
      "§8a doctrine: a rule about how an agent must treat content it did not write.",
    "matrix.product.claim_guardrails":
      "§8a doctrine: a rule about the claims an agent may make.",
    "showcase.live.user_signoff":
      "§8a proof that is genuinely a person; an agent minting it is what the design prevents.",
  ]

  /// The two rows the documents record as having nothing runnable, and why.
  ///
  /// The verifier half of the script was row 2's progress instrument: it
  /// started at 30 rows with nothing to run and row 2 drove it to these two.
  /// Both are written up as open, so both are pinned rather than silently
  /// tolerated, and a third row losing its verifier fails the suite.
  ///
  /// `showcase.live.user_signoff` appears here AND in ``doctrineRows``. That is
  /// the row itself, not a duplicate: its proof is a person, so it has neither
  /// a golden/bad/edge scenario nor a command to name as a verifier.
  static let rowsWithNothingRunnable: [String: String] = [
    "showcase.flow.revision_epoch_staleness":
      "scenario-conventions.md §10: implemented in the core but unreachable from the CLI; "
      + "deliberately unbound, because a new affordance is a decision 8 stop.",
    "showcase.live.user_signoff":
      "scenario-conventions.md §8a: the proof is a person, so there is no command to name.",
  ]

  // MARK: - Findings

  struct Finding: Hashable, Sendable {
    /// The row the finding is about, so findings can be grouped without
    /// re-parsing the message.
    let rowIdentifier: String
    /// The message, byte for byte what the `.mjs` printed.
    let text: String
  }

  private static func sorted(_ findings: [Finding]) -> [Finding] {
    findings.sorted { first, second in
      first.text < second.text
    }
  }

  /// Every scenario-convention finding over the live matrix, sorted.
  static func scenarioFindings(repositoryRoot: String) throws -> [Finding] {
    try sorted(check(repositoryRoot: repositoryRoot).scenario)
  }

  /// Every "nothing to run" finding over the live matrix, sorted.
  static func verifierFindings(repositoryRoot: String) throws -> [Finding] {
    try sorted(check(repositoryRoot: repositoryRoot).verifier)
  }

  /// The number of active rows the check walked, reported rather than asserted:
  /// the conventions document quotes 89 in one section and 98 in another, both
  /// measured on different days, so the population is not a thing to pin.
  static func activeRowCount(repositoryRoot: String) throws -> Int {
    try check(repositoryRoot: repositoryRoot).activeRows
  }

  struct Result: Sendable {
    var scenario: [Finding] = []
    var verifier: [Finding] = []
    var activeRows = 0
  }

  static func check(repositoryRoot: String) throws -> Result {
    var result = Result()
    let root = URL(fileURLWithPath: repositoryRoot, isDirectory: true)
    for file in try yamlFiles(in: root.appendingPathComponent(matrixDirectory, isDirectory: true)) {
      let relative = relativePath(of: file, under: repositoryRoot)
      let text = try String(contentsOf: file, encoding: .utf8)
      for row in rows(in: text) where row.lifecycle == "active" {
        result.activeRows += 1
        appendVerifierFindings(for: row, relativePath: relative, into: &result)
        appendScenarioFindings(for: row, relativePath: relative, into: &result)
      }
    }
    return result
  }

  // MARK: - The two checks

  /// Row 2 needs something to RUN. A row whose `required_verifiers` names an id
  /// its `verifiers:` block never defines is a dangling reference, and it reads
  /// exactly like a healthy row: `use-cases matrix validate` passes it with zero
  /// diagnostics, the same way it passed the dead `source_refs`.
  private static func appendVerifierFindings(
    for row: Row,
    relativePath: String,
    into result: inout Result,
  ) {
    if row.requiredVerifiers.isEmpty {
      if row.definedVerifiers.isEmpty {
        result.verifier.append(
          Finding(
            rowIdentifier: row.identifier,
            text: "\(relativePath): \(row.identifier) — no verifier at all; "
              + "nothing can run for this row",
          ),
        )
      }
      return
    }
    let undefined = row.requiredVerifiers.filter { identifier in
      !row.definedVerifiers.contains(identifier) && !builtInVerifiers.contains(identifier)
    }
    guard !undefined.isEmpty else {
      return
    }
    result.verifier.append(
      Finding(
        rowIdentifier: row.identifier,
        text: "\(relativePath): \(row.identifier) — required_verifiers names "
          + "\(undefined.joined(separator: ", ")), which no verifiers block defines",
      ),
    )
  }

  private static func appendScenarioFindings(
    for row: Row,
    relativePath: String,
    into result: inout Result,
  ) {
    func finding(_ suffix: String) -> Finding {
      Finding(rowIdentifier: row.identifier, text: "\(relativePath): \(suffix)")
    }

    guard !row.scenarios.isEmpty else {
      result.scenario.append(finding("\(row.identifier) — active with no scenarios"))
      return
    }

    // The id carries the kind: `<row-id>.golden|bad|edge|stress[_<qualifier>]`.
    let suffixes = row.scenarios.map { scenario -> String in
      let drop = row.identifier.count + 1
      return scenario.count <= drop ? "" : String(scenario.dropFirst(drop))
    }
    let kinds = ["golden", "bad", "edge", "stress"]
    func has(_ kind: String) -> Bool {
      suffixes.contains { suffix in
        suffix == kind || suffix.hasPrefix("\(kind)_")
      }
    }

    for suffix in suffixes where !kinds.contains(where: { kind in
      suffix == kind || suffix.hasPrefix("\(kind)_")
    }) {
      result.scenario.append(
        finding("\(row.identifier).\(suffix) — scenario id does not start golden/bad/edge/stress"),
      )
    }
    if !has("golden") {
      result.scenario.append(finding("\(row.identifier) — no golden scenario"))
    }
    if !has("bad"), !row.tags.contains("no-bad-path") {
      result.scenario.append(
        finding("\(row.identifier) — no bad scenario, and no no-bad-path tag saying why"),
      )
    }
    if !has("edge"), !row.tags.contains("no-edge-path") {
      result.scenario.append(
        finding("\(row.identifier) — no edge scenario, and no no-edge-path tag saying why"),
      )
    }
  }

  // MARK: - The line reader

  struct Row: Sendable {
    var identifier: String
    var lifecycle: String?
    var tags: [String] = []
    var scenarios: [String] = []
    var definedVerifiers: [String] = []
    var requiredVerifiers: [String] = []
  }

  /// A deliberately small line reader rather than a YAML dependency, carried
  /// over from the script unchanged.
  ///
  /// Two reasons it stayed a line reader. The script's comment gives the first:
  /// it was meant for a git hook, where parsing the whole matrix costs more
  /// than the check is worth. The second is the one that matters here — the
  /// oracle links nothing, so the only YAML reader available is `OracleYaml`,
  /// which throws on flow collections and anchors by design. A file carrying
  /// one would raise instead of producing a finding, and the count would stop
  /// matching the script's. A transliteration is provably faithful; a rewrite
  /// is not.
  static func rows(in text: String) -> [Row] {
    var reader = Reader()
    for line in text.components(separatedBy: "\n") {
      reader.consume(line)
    }
    return reader.rows
  }

  /// The reader's state. It is a type rather than three `var`s in a loop only
  /// so the line handler can split in two without losing the script's
  /// early-exit behaviour: `verifiers:` and `required_verifiers:` both `continue`
  /// past everything after them, which is why an open `required_verifiers:`
  /// block survives a `verifiers:` line.
  private struct Reader {
    var rows: [Row] = []
    var inVerifiers = false
    var inRequired = false

    mutating func consume(_ line: String) {
      if let identifier = ScenarioConventions.capture(line, prefix: "  - id: ") {
        rows.append(Row(identifier: identifier))
        inVerifiers = false
        inRequired = false
        return
      }
      guard !rows.isEmpty else {
        return
      }
      consumeRowFields(line)
      consumeVerifierBlocks(line)
    }

    private mutating func consumeRowFields(_ line: String) {
      let index = rows.count - 1
      if let lifecycle = ScenarioConventions.capture(line, prefix: "    lifecycle: ") {
        rows[index].lifecycle = lifecycle
      }
      // `- ` at six spaces is either a tag or a scenario entry; only the two
      // tags the convention recognises are collected, and the two patterns
      // cannot both match (a scenario line carries a space after `id:`).
      if let tag = ScenarioConventions.capture(line, prefix: "      - "),
         tag == "no-bad-path" || tag == "no-edge-path"
      {
        rows[index].tags.append(tag)
      }
      if let scenario = ScenarioConventions.capture(line, prefix: "      - id: ") {
        rows[index].scenarios.append(scenario)
      }
    }

    private mutating func consumeVerifierBlocks(_ line: String) {
      let index = rows.count - 1
      // `verifiers:` sits at 6 spaces under verification_policy; each verifier
      // id at 8. Any other 6-space-or-shallower key ends the block.
      if line == "      verifiers:" {
        inVerifiers = true
        return
      }
      if ScenarioConventions.isShallowKey(line) {
        inVerifiers = false
      }
      if inVerifiers, let defined = ScenarioConventions.definedVerifier(line) {
        rows[index].definedVerifiers.append(defined)
      }

      // `required_verifiers:` sits at 10 spaces inside a requirements entry;
      // its items at 12.
      if line == "          required_verifiers:" {
        inRequired = true
        return
      }
      guard inRequired else {
        return
      }
      if let required = ScenarioConventions.capture(line, prefix: "            - ") {
        rows[index].requiredVerifiers.append(required)
      } else {
        inRequired = false
      }
    }
  }

  /// `^<prefix>(\S+)$` — the shape every pattern in the script takes.
  private static func capture(
    _ line: String,
    prefix: String,
  ) -> String? {
    guard line.hasPrefix(prefix) else {
      return nil
    }
    let value = line.dropFirst(prefix.count)
    guard !value.isEmpty, !value.contains(where: \.isWhitespace) else {
      return nil
    }
    return String(value)
  }

  /// `^ {8}([a-z_]+):$`
  private static func definedVerifier(_ line: String) -> String? {
    guard line.hasPrefix("        "), !line.hasPrefix("         ") else {
      return nil
    }
    let rest = line.dropFirst(8)
    guard rest.hasSuffix(":") else {
      return nil
    }
    let name = rest.dropLast()
    guard !name.isEmpty, name.allSatisfy({ character in
      character.isLowercase && character.isASCII || character == "_"
    }) else {
      return nil
    }
    return String(name)
  }

  /// `^ {0,6}[a-z_]+:` — a key at six spaces or shallower, which closes an open
  /// `verifiers:` block. (The script also excluded `^ {8}`; that can never
  /// match this pattern, so the exclusion is dropped rather than transcribed.)
  private static func isShallowKey(_ line: String) -> Bool {
    let indent = line.prefix { character in
      character == " "
    }.count
    guard indent <= 6 else {
      return false
    }
    let rest = line.dropFirst(indent)
    let name = rest.prefix { character in
      character.isLowercase && character.isASCII || character == "_"
    }
    return !name.isEmpty && rest.dropFirst(name.count).hasPrefix(":")
  }

  // MARK: - Files

  /// Every `.yml`/`.yaml` under the matrix, sorted so a finding list is stable.
  static func yamlFiles(in directory: URL) throws -> [URL] {
    var found: [URL] = []
    let entries = try FileManager.default.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
    )
    for entry in entries.sorted(by: { first, second in first.path < second.path }) {
      let isDirectory = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?
        .isDirectory ?? false
      if isDirectory {
        try found.append(contentsOf: yamlFiles(in: entry))
      } else if entry.pathExtension == "yml" || entry.pathExtension == "yaml" {
        found.append(entry)
      }
    }
    return found
  }

  private static func relativePath(
    of file: URL,
    under root: String,
  ) -> String {
    let path = file.path
    let prefix = root.hasSuffix("/") ? root : root + "/"
    return path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : path
  }
}
