import Foundation

/// The only values the corpus does not compare literally, because they are
/// genuinely nondeterministic on both sides:
///
///   * an approval request's nonce and validity window (`jti`, `iat`, `exp`),
///     which are minted per call on purpose — a reused nonce would make the
///     request replayable;
///   * the instant a freshness scan or a plan was generated at
///     (`generated_at`, `evaluated_at`);
///   * an evidence event's UUIDv7 and the ledger shard derived from it;
///   * for `evidence_record` only, its `recorded_at` and `captured_at`: that
///     tool takes no timestamp argument, so the clock is the only source. Each
///     case names those fields itself, so no other case hides a clock.
///
/// Each field appears two ways in a response: plain inside a resource payload,
/// and backslash-escaped inside a tool result's `text` string. The same
/// substitution runs over the recorded line and the produced one, so a
/// mismatch anywhere else still fails.
enum McpCorpusNormalisation {
  private static let tokens = [
    "jti": "$JTI",
    "iat": "$IAT",
    "exp": "$EXP",
  ]

  static func applied(
    to text: String,
    clockFields: [String] = [],
  ) -> String {
    var result = text
    for field in ["jti", "iat", "exp", "generated_at", "evaluated_at"] + clockFields {
      let token = tokens[field] ?? "$NOW"
      for quote in ["\"", "\\\""] {
        result = replacedValues(
          in: result,
          opening: "\(quote)\(field)\(quote):\(quote)",
          closing: quote,
          token: token,
        )
      }
    }
    return replacedShard(in: replacedIdentifiers(in: result))
  }

  /// Every `"<field>":"<value>"` rewritten to the token, without a regex: the
  /// escaped form's backslashes make a pattern unreadable, and the value never
  /// contains a quote.
  private static func replacedValues(
    in text: String,
    opening: String,
    closing: String,
    token: String,
  ) -> String {
    var result = ""
    var remainder = Substring(text)
    while let start = remainder.range(of: opening) {
      result += remainder[remainder.startIndex ..< start.upperBound]
      let value = remainder[start.upperBound...]
      guard let end = value.range(of: closing) else {
        return result + value
      }
      result += token
      remainder = value[end.lowerBound...]
    }
    return result + remainder
  }

  /// Every UUID rewritten to `$UUID`. Only the evidence ledger uses one; the
  /// showcase ledger's ids are derived from pinned inputs and stay literal.
  private static func replacedIdentifiers(in text: String) -> String {
    let hexadecimal = Set("0123456789abcdef")
    let groups = [8, 4, 4, 4, 12]
    var result = ""
    let characters = Array(text)
    var index = 0
    while index < characters.count {
      if let length = uuidLength(characters, at: index, groups: groups, hexadecimal: hexadecimal) {
        result += "$UUID"
        index += length
        continue
      }
      result.append(characters[index])
      index += 1
    }
    return result
  }

  /// The length of the UUID starting at `index`, or nil when there is none.
  private static func uuidLength(
    _ characters: [Character],
    at index: Int,
    groups: [Int],
    hexadecimal: Set<Character>,
  ) -> Int? {
    var cursor = index
    for (position, length) in groups.enumerated() {
      if position > 0 {
        guard cursor < characters.count, characters[cursor] == "-" else {
          return nil
        }
        cursor += 1
      }
      for _ in 0 ..< length {
        guard cursor < characters.count, hexadecimal.contains(characters[cursor]) else {
          return nil
        }
        cursor += 1
      }
    }
    return cursor - index
  }

  /// `by-id/<two hex>/` is the first byte of the event's UUID, so it moves with
  /// it.
  private static func replacedShard(in text: String) -> String {
    let hexadecimal = Set("0123456789abcdef")
    var result = ""
    var remainder = Substring(text)
    let opening = "by-id/"
    while let start = remainder.range(of: opening) {
      result += remainder[remainder.startIndex ..< start.upperBound]
      let rest = remainder[start.upperBound...]
      let shard = rest.prefix(2)
      if shard.count == 2, shard.allSatisfy(hexadecimal.contains),
         rest.dropFirst(2).first == "/"
      {
        result += "$SHARD"
        remainder = rest.dropFirst(2)
      } else {
        remainder = rest
      }
    }
    return result + remainder
  }
}
