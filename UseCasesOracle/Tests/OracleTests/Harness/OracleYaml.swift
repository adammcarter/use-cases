import Foundation

/// The YAML the oracle reads off a GitHub Actions workflow.
///
/// Same reasoning as `OracleJson`: the oracle links nothing, so it cannot borrow
/// `UseCasesCore`'s YAML reader — a black-box test that parsed a workflow with
/// the product's own parser would stop being black-box the moment that parser
/// was wrong. The TypeScript side used the `yaml` npm package; this is the
/// independent replacement.
///
/// It is deliberately SMALL and deliberately LOUD. It understands block
/// mappings, block sequences, literal/folded scalars and comments — the whole of
/// what a workflow file is — and it THROWS on anything else (flow collections,
/// anchors, aliases, tags, documents). A reader that quietly returned an empty
/// mapping would make every "this key is absent" assertion pass having read
/// nothing, which is the same silent-green the oracle exists to prevent.
///
/// One simplification worth naming: `on:` is a key like any other here. In YAML
/// 1.1 it is a boolean, which is why the TypeScript had to look for `workflow.on
/// ?? workflow["true"]`; that dance disappears.
indirect enum OracleYaml: Sendable, Equatable {
  case scalar(String)
  case mapping([String: OracleYaml])
  case sequence([OracleYaml])

  enum Failure: Error, CustomStringConvertible {
    case unsupported(line: Int, text: String, reason: String)

    var description: String {
      switch self {
      case let .unsupported(line, text, reason):
        "OracleYaml: line \(line) is not supported (\(reason)): \(text)"
      }
    }
  }

  static func parse(_ text: String) throws -> OracleYaml {
    var lines = text.components(separatedBy: "\n").enumerated().map { index, raw in
      Line(number: index + 1, text: raw)
    }
    // A leading document marker is the only directive form that appears in
    // these files; anything else is refused below.
    lines = lines.filter { line in
      line.trimmed != "---"
    }
    var reader = Reader(lines: lines)
    return try reader.node(minimumIndent: 0)
  }

  subscript(key: String) -> OracleYaml? {
    guard case let .mapping(members) = self else {
      return nil
    }
    return members[key]
  }

  var stringValue: String? {
    guard case let .scalar(value) = self else {
      return nil
    }
    return value
  }

  var mappingValue: [String: OracleYaml]? {
    guard case let .mapping(members) = self else {
      return nil
    }
    return members
  }

  var sequenceValue: [OracleYaml]? {
    guard case let .sequence(elements) = self else {
      return nil
    }
    return elements
  }

  /// The keys of a mapping, sorted — what the TypeScript's
  /// `Object.keys(on).sort()` answers.
  var sortedKeys: [String] {
    (mappingValue ?? [:]).keys.sorted()
  }

  private struct Line: Sendable {
    let number: Int
    let text: String

    var isBlank: Bool {
      text.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var isComment: Bool {
      trimmed.hasPrefix("#")
    }

    var trimmed: String {
      text.trimmingCharacters(in: .whitespaces)
    }

    var indent: Int {
      text.prefix { character in
        character == " "
      }.count
    }
  }

  private struct Reader {
    let lines: [Line]
    var position = 0

    init(lines: [Line]) {
      self.lines = lines
    }

    mutating func skipIgnorable() {
      while position < lines.count, lines[position].isBlank || lines[position].isComment {
        position += 1
      }
    }

    var current: Line? {
      position < lines.count ? lines[position] : nil
    }

    /// Parse the node beginning at the current line, whose content is indented
    /// at least `minimumIndent`.
    mutating func node(minimumIndent: Int) throws -> OracleYaml {
      skipIgnorable()
      guard let first = current, first.indent >= minimumIndent else {
        return .scalar("")
      }
      if first.trimmed == "-" || first.trimmed.hasPrefix("- ") {
        return try sequence(indent: first.indent)
      }
      return try mapping(indent: first.indent)
    }

    mutating func mapping(indent: Int) throws -> OracleYaml {
      var members: [String: OracleYaml] = [:]
      while true {
        skipIgnorable()
        guard let line = current, line.indent >= indent else {
          break
        }
        if line.indent > indent {
          throw Failure.unsupported(
            line: line.number,
            text: line.text,
            reason: "unexpected indentation inside a mapping",
          )
        }
        guard let (key, rest) = Self.splitKey(line.trimmed) else {
          throw Failure.unsupported(
            line: line.number,
            text: line.text,
            reason: "expected `key:`",
          )
        }
        position += 1
        members[key] = try value(after: rest, keyIndent: indent, at: line)
      }
      return .mapping(members)
    }

    mutating func sequence(indent: Int) throws -> OracleYaml {
      var elements: [OracleYaml] = []
      while true {
        skipIgnorable()
        guard let line = current, line.indent == indent, line.trimmed.hasPrefix("-") else {
          break
        }
        let rest = String(line.trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        position += 1
        if rest.isEmpty {
          try elements.append(node(minimumIndent: indent + 1))
        } else if let (key, tail) = Self.splitKey(rest) {
          // `- key: value`, possibly with more keys indented beneath it. The
          // item's mapping starts two columns in, where the `- ` ended.
          var members: [String: OracleYaml] = [:]
          members[key] = try value(after: tail, keyIndent: indent + 2, at: line)
          if let next = current, next.indent > indent, !next.trimmed.hasPrefix("- ") {
            guard case let .mapping(rest) = try mapping(indent: next.indent) else {
              throw Failure.unsupported(
                line: next.number,
                text: next.text,
                reason: "expected the rest of a sequence item's mapping",
              )
            }
            members.merge(rest) { existing, _ in
              existing
            }
          }
          elements.append(.mapping(members))
        } else {
          try elements.append(.scalar(Self.scalar(rest, at: line)))
        }
      }
      return .sequence(elements)
    }

    /// The value of `key:` — inline, a block scalar, or a nested node.
    mutating func value(
      after rest: String,
      keyIndent: Int,
      at line: Line,
    ) throws -> OracleYaml {
      if rest.isEmpty {
        skipIgnorable()
        guard let next = current else {
          return .scalar("")
        }
        if next.indent > keyIndent {
          return try node(minimumIndent: next.indent)
        }
        // A sequence may sit at the key's own indentation.
        if next.indent == keyIndent, next.trimmed.hasPrefix("-") {
          return try sequence(indent: keyIndent)
        }
        return .scalar("")
      }
      if rest.hasPrefix("|") || rest.hasPrefix(">") {
        return .scalar(blockScalar(keyIndent: keyIndent))
      }
      return try .scalar(Self.scalar(rest, at: line))
    }

    /// A literal or folded block: every following line indented past the key.
    /// The body is returned as text — these tests only ever search it.
    mutating func blockScalar(keyIndent: Int) -> String {
      var body: [String] = []
      while let line = current, line.isBlank || line.indent > keyIndent {
        body.append(line.text)
        position += 1
      }
      return body.joined(separator: "\n")
    }

    /// `key: rest`, or nil when the line is not a mapping entry.
    static func splitKey(_ text: String) -> (String, String)? {
      guard let colon = text.firstIndex(of: ":") else {
        return nil
      }
      let key = String(text[text.startIndex ..< colon])
      let after = text.index(after: colon)
      let rest = String(text[after...])
      guard !key.isEmpty, !key.contains(" "), rest.isEmpty || rest.hasPrefix(" ") else {
        return nil
      }
      return (
        unquote(key),
        rest.trimmingCharacters(in: .whitespaces),
      )
    }

    /// A plain, single- or double-quoted scalar, with a trailing comment
    /// removed. Flow collections, anchors and tags are refused rather than
    /// guessed at.
    static func scalar(
      _ text: String,
      at line: Line,
    ) throws -> String {
      for (prefix, reason) in [
        ("[", "flow sequence"),
        ("{", "flow mapping"),
        ("&", "anchor"),
        ("*", "alias"),
        ("!", "tag"),
      ] where text.hasPrefix(prefix) {
        throw Failure.unsupported(line: line.number, text: line.text, reason: reason)
      }
      if text.hasPrefix("\"") || text.hasPrefix("'") {
        return unquote(text)
      }
      guard let comment = text.range(of: " #") else {
        return text
      }
      return String(text[text.startIndex ..< comment.lowerBound])
        .trimmingCharacters(in: .whitespaces)
    }

    static func unquote(_ text: String) -> String {
      for quote in ["\"", "'"] where text.hasPrefix(quote) && text.hasSuffix(quote)
        && text.count >= 2
      {
        return String(text.dropFirst().dropLast())
      }
      return text
    }
  }
}
