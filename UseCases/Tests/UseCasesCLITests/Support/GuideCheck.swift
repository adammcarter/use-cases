import ArgumentParser
import Foundation
@testable import UseCasesCLI

/// Reads a page of text that tells people how to use the tool, a guide or a skill, and checks
/// that everything it names is real: each `use-cases <command>`, each `--flag`, each file, each
/// agent tool (`use_cases_…`) and each argument the page gives a tool (`GuideToolCheck`).
///
/// It reads names only. What a page shows a command or a tool printing is not checked here: an
/// example of output can be out of date and still pass.
///
/// A command or a flag of the design that this build has not built yet is not a failure; it is
/// a gap, the way `CiRecipeCommandTests` treats one.
struct GuideCheck {
  /// What a page names that is not real, and what it names that is designed and not built yet.
  struct Findings: Equatable {
    var problems: [String] = []
    var gaps: [String] = []
  }

  /// The flags each built command reads, global ones included.
  private let builtFlags: [String: Set<String>]

  /// The flags the command list of the design names, built or not.
  private let designedFlags: Set<String>

  private let fileNames: Set<String>

  /// The tools of the MCP server, and the arguments each takes.
  private let toolCheck: GuideToolCheck

  init(
    builtFlags: [String: Set<String>],
    designedFlags: Set<String>,
    fileNames: Set<String>,
    toolCheck: GuideToolCheck = GuideToolCheck(
      tools: [:],
      fieldNames: [],
    ),
  ) {
    self.builtFlags = builtFlags
    self.designedFlags = designedFlags
    self.fileNames = fileNames
    self.toolCheck = toolCheck
  }

  /// The check against this build's own command tree and the files it creates.
  static func current() async throws -> GuideCheck {
    var builtFlags: [String: Set<String>] = [:]

    for command in UseCasesCommand.configuration.subcommands {
      let name = command.configuration.commandName ?? ""
      let help = UseCasesCommand.helpMessage(
        for: command,
        columns: 1000,
      )

      builtFlags[name] = optionNames(in: help)
    }

    return try await GuideCheck(
      builtFlags: builtFlags,
      designedFlags: flagNames(in: CommandList.text),
      fileNames: ProductFileNames.current(),
      toolCheck: GuideToolCheck.current(),
    )
  }

  /// Everything in the text that is not real, and every gap.
  func findings(in text: String) throws -> Findings {
    var found = Findings()
    let code = Self.codeText(in: text)

    for name in try Self.names(in: code, matching: #"use-cases ([a-z][a-z-]*)"#) {
      guard let designed = DesignedCommand(rawValue: name) else {
        found.problems.append("`use-cases \(name)` is not a command")
        continue
      }

      if !designed.isBuilt {
        found.gaps.append("`use-cases \(name)` is not built yet")
      }
    }

    for arguments in try RecipeCommands.arguments(in: code) {
      guard let flags = builtFlags[arguments[0]] else {
        continue
      }

      // A bare `--` ends the options, so a query word may start with a minus (chapter 16 §15).
      for word in arguments.dropFirst() where word.hasPrefix("--") && word != "--" {
        let flag = String(word.prefix { $0 != "=" })

        if !flags.contains(flag) {
          found.problems.append("`use-cases \(arguments[0])` has no \(flag)")
        }
      }
    }

    let known = Set(builtFlags.values.joined()).union(["--help", "--version"])

    for flag in Self.flagNames(in: Self.withoutGitsNoVerify(text)).sorted()
      where !known.contains(flag)
    {
      if designedFlags.contains(flag) {
        found.gaps.append("\(flag) is not built yet")
      } else {
        found.problems.append("\(flag) is not a flag")
      }
    }

    try check(
      fileNamesIn: text,
      into: &found,
    )

    found.problems += toolCheck.problems(in: text)

    return found
  }

  private func check(
    fileNamesIn text: String,
    into found: inout Findings,
  ) throws {
    let pattern = #"[A-Za-z0-9_.][A-Za-z0-9_./-]*\.(?:yml|yaml|jsonl?|md)\b"#

    for path in try Self.names(in: text, matching: "(" + pattern + ")") {
      let base = URL(fileURLWithPath: path).lastPathComponent

      // The files a person writes in the definitions folder have names of their own.
      if path.hasPrefix("use-cases/") || fileNames.contains(base) {
        continue
      }

      if path.hasPrefix("docs/") {
        found.gaps.append("\(path) is a file of the design, not of the tool")
      } else {
        found.problems.append("\(path) is not a file the tool reads or writes")
      }
    }
  }

  /// The text inside backticks and inside fenced code blocks, a line each.
  static func codeText(in text: String) -> String {
    var lines: [String] = []
    var isFenced = false

    for line in text.components(separatedBy: "\n") {
      if line.hasPrefix("```") {
        isFenced.toggle()
      } else if isFenced {
        lines.append(line)
      } else {
        lines += line.matches(of: /`([^`]+)`/).map(\.output.1).map(String.init)
      }
    }

    return lines.joined(separator: "\n")
  }

  /// The text without git's own `--no-verify` where it is named as git's: a word of a `git`
  /// command, as in `git commit --no-verify` (chapter 18). The tool has no such flag.
  static func withoutGitsNoVerify(_ text: String) -> String {
    text.replacing(/(\bgit[ \t]+[a-z][a-z-]*(?:[ \t]+[^\s`;|&]+)*?)[ \t]+--no-verify\b/) { match in
      match.output.1
    }
  }

  /// Every `--flag` in the text.
  static func flagNames(in text: String) -> Set<String> {
    Set(
      text.matches(of: /(?:^|[^\w-])(--[a-z][a-z-]*)/).map(\.output.1).map(String.init),
    )
  }

  /// The option each line of a help message begins with.
  private static func optionNames(in help: String) -> Set<String> {
    Set(
      help.matches(of: /(?m)^\s+(?:-\w,\s*)?(--[a-z][a-z-]*)/).map(\.output.1).map(String.init),
    )
  }

  private static func names(
    in text: String,
    matching pattern: String,
  ) throws -> [String] {
    try text.matches(of: Regex(pattern)).compactMap { match in
      match.output[1].substring.map(String.init)
    }
  }
}
