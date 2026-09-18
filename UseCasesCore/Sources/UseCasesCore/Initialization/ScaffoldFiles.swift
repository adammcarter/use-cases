import Foundation

/// The files init merges into rather than replaces: `.gitignore`, `AGENTS.md`
/// and the git hooks, each append-only over what the repository already has.
struct ScaffoldFiles {
  static let gitignoreFile = ".gitignore"
  static let agentsMarkdownFile = "AGENTS.md"
  static let decisionHeading = "## Use-case driven development"

  /// Transient output the tool produces, which must stay out of git.
  private static let gitignoreEntries: [(pattern: String, comment: String)] = [
    ("showcase-runs/", "# use-cases: transient showcase run output (not durable evidence)."),
    (
      ".use-cases/verification-results.jsonl",
      "# use-cases: transient local verification results (the verify -> prove handoff).",
    ),
  ]

  let repositoryRoot: String

  // MARK: - Filesystem

  func makeDirectories(_ path: String) throws(WorkspaceScaffoldError) {
    do throws(FileAccessError) {
      try NodeFile.makeDirectories(atPath: path)
    } catch {
      throw .fileAccess(error)
    }
  }

  func write(
    _ text: String,
    to path: String,
  ) throws(WorkspaceScaffoldError) {
    do throws(FileAccessError) {
      try NodeFile.writeText(text, atPath: path)
    } catch {
      throw .fileAccess(error)
    }
  }

  /// `existsSync(path) ? readFileSync(path, "utf8") : null`.
  private func readIfExists(_ path: String) throws(WorkspaceScaffoldError) -> String? {
    guard NodeFile.exists(atPath: path) else {
      return nil
    }
    do throws(FileAccessError) {
      return try NodeFile.readText(atPath: path)
    } catch {
      throw .fileAccess(error)
    }
  }

  // MARK: - .gitignore

  /// Appends each missing entry, with its comment; a line that trims to the
  /// pattern counts as present. True when the file was created or changed.
  func ensureGitignoreEntries() throws(WorkspaceScaffoldError) -> Bool {
    let path = repositoryRoot + "/" + Self.gitignoreFile
    let existing = try readIfExists(path)
    let present = Set(JavaScriptString.split(existing ?? "", on: 0x0A).map(JavaScriptString.trim))
    let missing = Self.gitignoreEntries.filter { entry in
      !present.contains(entry.pattern)
    }
    guard !missing.isEmpty else {
      return false
    }
    let additions = missing.flatMap { entry in
      [entry.comment, entry.pattern]
    }.joined(separator: "\n")
    guard let existing else {
      try write(additions + "\n", to: path)
      return true
    }
    let separator = existing.isEmpty || CodeUnitText.hasSuffixLineFeed(existing) ? "" : "\n"
    let spacer = JavaScriptString.trim(existing).isEmpty ? "" : "\n"
    try write(existing + separator + spacer + additions + "\n", to: path)
    return true
  }

  // MARK: - AGENTS.md

  /// Records `yes` under the decision heading unless the heading is already
  /// there, in which case the first `yes` or `no` starting a line after it is
  /// read back.
  func ensureAgentsMarkdownDecision(today: String) throws(WorkspaceScaffoldError)
    -> AgentsMarkdownOutcome
  {
    let path = repositoryRoot + "/" + Self.agentsMarkdownFile
    let existing = try readIfExists(path)

    if let existing, let headingIndex = CodeUnitText.firstIndex(
      of: Self.decisionHeading,
      in: existing,
    ) {
      let after = Array(existing.utf16)[(headingIndex + Self.decisionHeading.utf16.count)...]
      return AgentsMarkdownOutcome(
        status: .alreadyRecorded,
        decision: Self.recordedDecision(in: Array(after)),
      )
    }

    let section = [
      Self.decisionHeading,
      "",
      "yes \u{2014} \(today)",
      "",
      "This repo is use-case driven: every functional change starts in `use-cases/`,",
      "rows are agreed before tests, tests and code are wrapped in the row's markers,",
      "and `use-cases scan` is the coverage number. The rules live in the Use Cases plugin's",
      "skills \u{2014} `use-case-driven-development` for when and in what order, `use-cases`",
      "for the commands \u{2014} and every agent working here follows them.",
      "",
    ].joined(separator: "\n")

    guard let existing else {
      try write("# \(WorkspaceScaffold.baseName(of: repositoryRoot))\n\n\(section)", to: path)
      return AgentsMarkdownOutcome(status: .created, decision: .agreed)
    }
    let separator = CodeUnitText.hasSuffixLineFeed(existing) ? "" : "\n"
    let spacer = JavaScriptString.trim(existing).isEmpty ? "" : "\n"
    try write(existing + separator + spacer + section, to: path)
    return AgentsMarkdownOutcome(status: .appended, decision: .agreed)
  }

  /// `after.match(/^\s*(yes|no)\b/m)?.[1]`: at the first line start (the text's
  /// start, or after `\n`, `\r`, U+2028 or U+2029) where optional whitespace is
  /// followed by `yes` or `no` and then a non-word code unit or the end.
  static func recordedDecision(in units: [UInt16]) -> AgentsMarkdownOutcome.Decision {
    for start in 0 ... units.count {
      guard start == 0 || isLineTerminator(units[start - 1]) else {
        continue
      }
      var position = start
      while position < units.count, CodeUnits.isJavaScriptWhitespace(units[position]) {
        position += 1
      }
      for (word, decision) in [("yes", AgentsMarkdownOutcome.Decision.agreed), ("no", .declined)] {
        let wordUnits = Array(word.utf16)
        let end = position + wordUnits.count
        guard end <= units.count, units[position ..< end].elementsEqual(wordUnits) else {
          continue
        }
        if end == units.count || !isWordUnit(units[end]) {
          return decision
        }
      }
    }
    return .unknown
  }

  private static func isLineTerminator(_ unit: UInt16) -> Bool {
    unit == 0x0A || unit == 0x0D || unit == 0x2028 || unit == 0x2029
  }

  private static func isWordUnit(_ unit: UInt16) -> Bool {
    CodeUnits.isASCIILetter(unit) || CodeUnits.isASCIIDigit(unit) || unit == 0x5F
  }

  // MARK: - Git hooks

  struct HooksOutcome {
    let directory: String
    let isHooksPathSet: Bool
    let written: [String]
    let extended: [String]
  }

  /// Writes or extends pre-commit and pre-push in the configured hooks
  /// directory (`.githooks` when none), marks them executable, and points
  /// core.hooksPath at `.githooks` in a repository that had none configured.
  func ensureGitHooks(git: some ScaffoldGitRunning) throws(WorkspaceScaffoldError) -> HooksOutcome {
    let isGitRepository = git.run(["rev-parse", "--git-dir"], workingDirectory: repositoryRoot)
      .exitStatus == 0
    let configured = isGitRepository
      ? JavaScriptString.trim(
        git.run(["config", "--get", "core.hooksPath"], workingDirectory: repositoryRoot)
          .standardOutput,
      )
      : ""
    let directory = configured.isEmpty ? WorkspaceScaffold.defaultHooksDirectory : configured
    var written: [String] = []
    var extended: [String] = []

    for (name, block) in [
      ("pre-commit", ScaffoldTemplates.preCommitBlock),
      ("pre-push", ScaffoldTemplates.prePushBlock),
    ] {
      let relativePath = WorkspacePath.normalize(directory + "/" + name)
      switch try writeHook(block.joined(separator: "\n"), relativePath: relativePath) {
      case .written: written.append(relativePath)
      case .extended: extended.append(relativePath)
      case .alreadyPresent: continue
      }
    }

    var isHooksPathSet = false
    if isGitRepository, configured.isEmpty {
      isHooksPathSet = git.run(
        ["config", "core.hooksPath", WorkspaceScaffold.defaultHooksDirectory],
        workingDirectory: repositoryRoot,
      ).exitStatus == 0
    }
    return HooksOutcome(
      directory: directory,
      isHooksPathSet: isHooksPathSet,
      written: written,
      extended: extended,
    )
  }

  private enum HookWrite {
    case written
    case extended
    case alreadyPresent
  }

  /// One hook: a new file, or the block appended to a hook that does not
  /// carry it yet, then made executable. A hook already carrying the block is
  /// left exactly as it is, mode included.
  private func writeHook(
    _ body: String,
    relativePath: String,
  ) throws(WorkspaceScaffoldError) -> HookWrite {
    let absolutePath: String
    do throws(PathError) {
      absolutePath = try PathContainment.resolveContained(
        root: repositoryRoot,
        candidate: relativePath,
        message: "Hook target escapes the repo boundary.",
      )
    } catch {
      throw .pathEscape(error)
    }
    try makeDirectories(WorkspacePath.dirname(absolutePath))
    let outcome: HookWrite
    if let existing = try readIfExists(absolutePath) {
      if CodeUnitText.firstIndex(of: ScaffoldTemplates.hookBlockMarker, in: existing) != nil {
        return .alreadyPresent
      }
      let separator = CodeUnitText.hasSuffixLineFeed(existing) ? "" : "\n"
      try write(existing + separator + "\n" + body + "\n", to: absolutePath)
      outcome = .extended
    } else {
      try write("#!/usr/bin/env bash\n" + body + "\n", to: absolutePath)
      outcome = .written
    }
    guard chmod(absolutePath, 0o755) == 0 else {
      throw .fileAccess(FileAccessError(errorNumber: errno, operation: "chmod", path: absolutePath))
    }
    return outcome
  }
}
