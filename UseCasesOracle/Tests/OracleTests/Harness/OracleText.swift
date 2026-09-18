import Foundation

/// Regular expressions, for the oracle files that read shipped text.
///
/// Several black-box files inspect artefacts rather than output — skill and
/// agent bodies, the CLI's own help — and in TypeScript they do it with literal
/// `/…/` regexes. This is the same reading, once, so a port does not grow a
/// hand-rolled scanner per file.
enum OracleText {
  /// Every match's capture groups, group 0 first. A group that did not
  /// participate is nil.
  static func matches(
    _ pattern: String,
    in text: String,
  ) -> [[String?]] {
    guard let expression = try? NSRegularExpression(pattern: pattern) else {
      return []
    }
    let whole = NSRange(text.startIndex ..< text.endIndex, in: text)
    return expression.matches(in: text, range: whole).map { match in
      (0 ..< match.numberOfRanges).map { group in
        guard let range = Range(match.range(at: group), in: text) else {
          return nil
        }
        return String(text[range])
      }
    }
  }

  static func firstMatch(
    _ pattern: String,
    in text: String,
  ) -> [String?]? {
    matches(pattern, in: text).first
  }

  static func contains(
    _ pattern: String,
    in text: String,
  ) -> Bool {
    firstMatch(pattern, in: text) != nil
  }

  /// A skill or agent file's YAML frontmatter, as flat key/value pairs.
  static func frontmatter(of source: String) -> [String: String]? {
    guard let match = firstMatch("(?s)\\A---\\n(.*?)\\n---\\n", in: source),
          let body = match[1]
    else {
      return nil
    }
    var fields: [String: String] = [:]
    for line in body.split(separator: "\n", omittingEmptySubsequences: false) {
      guard let pair = firstMatch("^([a-z_]+):\\s*(.*)$", in: String(line)),
            let key = pair[1],
            let value = pair[2]
      else {
        continue
      }
      fields[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }
    return fields
  }
}
