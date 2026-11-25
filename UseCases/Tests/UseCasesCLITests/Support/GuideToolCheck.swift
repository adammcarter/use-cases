import Foundation
@testable import UseCasesMCP

/// Checks what a page says about the agents' tools: that each `use_cases_…` it names is a tool
/// the MCP server offers, and that each argument it gives a tool is one that tool takes.
///
/// The tools are read from the catalogue the server serves (`ToolDefinition.all`), never from a
/// copy. Only the forms the pages use are read: a row of a table that starts with a tool, a tool
/// followed by "with" or "takes" up to the end of the clause, and "every tool (but …) takes".
/// What a tool prints back is not checked here: a field of its answer (`text`, `gate.passed`)
/// is never read as an argument.
struct GuideToolCheck {
  /// What one tool takes: its arguments, and the values its arguments allow.
  struct Terms: Equatable {
    var arguments: Set<String>
    var values: Set<String> = []
  }

  private let tools: [String: Terms]

  /// The `use_cases_…` names that are fields of the product's files, not tools
  /// (`use_cases_dir`).
  private let fieldNames: Set<String>

  init(
    tools: [String: Terms],
    fieldNames: Set<String>,
  ) {
    self.tools = tools
    self.fieldNames = fieldNames
  }

  /// The check against the tools this build serves, and the fields of its own schemas.
  static func current() throws -> GuideToolCheck {
    var tools: [String: Terms] = [:]

    for definition in ToolDefinition.all {
      tools[definition.name] = Terms(
        arguments: Set(definition.arguments.map(\.name)),
        values: Set(definition.arguments.flatMap(\.allowedValues)),
      )
    }

    return try GuideToolCheck(
      tools: tools,
      fieldNames: schemaFieldNames(),
    )
  }

  /// Every tool the text names that is not served, and every argument it gives a tool that the
  /// tool does not take.
  func problems(in text: String) -> [String] {
    var problems: [String] = []
    var named: Set<String> = []

    for match in text.matches(of: /\buse_cases_[a-z_]*[a-z]/) {
      let name = String(match.output)

      if tools[name] == nil, !fieldNames.contains(name), named.insert(name).inserted {
        problems.append("`\(name)` is not a tool the server offers")
      }
    }

    for line in text.components(separatedBy: "\n") {
      problems += tableProblems(in: line)
    }

    problems += clauseProblems(in: text)
    problems += everyToolProblems(in: text)

    return problems
  }

  /// A row such as `| \`use_cases_show\` | \`use-cases show\` | \`use_case\` |`: every word in
  /// backticks after the tool is one of its arguments, or a value one of them takes.
  private func tableProblems(in line: String) -> [String] {
    guard let row = line.firstMatch(of: /^\|\s*`(use_cases_[a-z_]+)`\s*\|(.*)$/) else {
      return []
    }

    return unknownTerms(
      in: String(row.output.2),
      of: String(row.output.1),
    )
  }

  /// "\`use_cases_render\` with \`kind\` \`brief\`", "the \`use_cases_search\` tool takes
  /// \`query\`": every word in backticks up to the end of the clause, or the next tool.
  private func clauseProblems(in text: String) -> [String] {
    let clauses = text.matches(
      of: /`(use_cases_[a-z_]+)`(?: tool)? (?:with|takes) ([^.:;\n]*)/,
    )

    return clauses.filter { clause in
      // "every tool but \`use_cases_docs\` takes …" is a claim about the other tools.
      !text[..<clause.range.lowerBound].hasSuffix("but ")
    }.flatMap { clause in
      let words = String(clause.output.2)
      let own = words.firstRange(of: "`use_cases_").map { range in
        String(words[..<range.lowerBound])
      } ?? words

      return unknownTerms(
        in: own,
        of: String(clause.output.1),
      )
    }
  }

  /// "Every tool but \`use_cases_docs\` takes \`workspace\`": exactly the tools not named take it.
  private func everyToolProblems(in text: String) -> [String] {
    let claims = text.matches(
      of: /(?i)every tool(?: but ([^.]*?))? (?:also )?takes `([a-z_]+)`/,
    )

    return claims.flatMap { claim in
      let argument = String(claim.output.2)
      let exceptions = Set(
        (claim.output.1.map(String.init) ?? "").matches(of: /use_cases_[a-z_]+/).map { name in
          String(name.output)
        },
      )

      return tools.keys.sorted().compactMap { tool -> String? in
        let takes = tools[tool]?.arguments.contains(argument) == true

        if takes == exceptions.contains(tool) {
          let verb = takes ? "takes" : "does not take"

          return "`\(tool)` \(verb) `\(argument)`, unlike the page says"
        }

        return nil
      }
    }
  }

  private func unknownTerms(
    in words: String,
    of tool: String,
  ) -> [String] {
    guard let terms = tools[tool] else {
      return []
    }

    return words.matches(of: /`([a-z][a-z_]*)`/).map { word in
      String(word.output.1)
    }.filter { word in
      !word.hasPrefix("use_cases_") && !terms.arguments.contains(word)
        && !terms.values.contains(word)
    }.map { word in
      "`\(tool)` takes no `\(word)`"
    }
  }

  /// The `use_cases_…` names the product's own schemas give its files' fields.
  private static func schemaFieldNames() throws -> Set<String> {
    let folder = try DocsFolder.url().deletingLastPathComponent()
      .appending(path: "UseCases/Sources/UseCasesCore/Resources/Schemas")
    var names: Set<String> = []

    for file in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
      let text = try String(
        contentsOf: folder.appending(path: file),
        encoding: .utf8,
      )

      names.formUnion(
        text.matches(of: /"(use_cases_[a-z_]+)"/).map { match in
          String(match.output.1)
        },
      )
    }

    return names
  }
}
