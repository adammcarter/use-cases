/// One word of a POSIX shell script, written and read back.
///
/// Everything here works scalar by scalar. A shell sees bytes, so a quote or a backtick followed
/// by a combining mark is still a quote or a backtick to it, though Swift calls the pair one
/// character.
enum ShellWord {
  private static let safe = Set(
    "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@%+=:,./-_".unicodeScalars,
  )

  private static let escapedInDoubleQuotes: Set<Unicode.Scalar> = ["\"", "\\", "$", "`"]

  /// The word as a shell reads it back as `text`: bare when every character is safe, otherwise
  /// in single quotes, a quote inside them written `'\''`.
  static func quoting(_ text: String) -> String {
    guard !text.isEmpty else {
      return "''"
    }

    if text.unicodeScalars.allSatisfy(safe.contains) {
      return text
    }

    var quoted = String.UnicodeScalarView()
    quoted.append("'")

    for scalar in text.unicodeScalars {
      if scalar == "'" {
        quoted.append(contentsOf: "'\\''".unicodeScalars)
      } else {
        quoted.append(scalar)
      }
    }

    quoted.append("'")

    return String(quoted)
  }

  /// The text in double quotes, where `"`, `\`, `$` and a backtick would still mean something to
  /// the shell: each is escaped with a backslash.
  static func doubleQuoting(_ text: String) -> String {
    var quoted = String.UnicodeScalarView()
    quoted.append("\"")

    for scalar in text.unicodeScalars {
      if escapedInDoubleQuotes.contains(scalar) {
        quoted.append("\\")
      }

      quoted.append(scalar)
    }

    quoted.append("\"")

    return String(quoted)
  }

  /// The word that starts `text`, as a shell would read it, and what follows it. The word is
  /// made of bare safe characters, single-quoted parts, `\'` and `"'"`, whichever way a build
  /// wrote its quotes. `nil` when `text` does not start with a word.
  static func reading(
    _ text: Substring.UnicodeScalarView,
  ) -> (word: String, rest: Substring.UnicodeScalarView)? {
    var word = String.UnicodeScalarView()
    var rest = text

    while let first = rest.first {
      if safe.contains(first) {
        word.append(first)
        rest = rest.dropFirst()
      } else if first == "'" {
        let body = rest.dropFirst()

        guard let close = body.firstIndex(of: "'") else {
          return nil
        }

        word.append(contentsOf: body[..<close])
        rest = body[body.index(after: close)...]
      } else if rest.starts(with: "\\'".unicodeScalars) {
        word.append("'")
        rest = rest.dropFirst(2)
      } else if rest.starts(with: "\"'\"".unicodeScalars) {
        word.append("'")
        rest = rest.dropFirst(3)
      } else {
        break
      }
    }

    return rest.startIndex == text.startIndex ? nil : (String(word), rest)
  }
}
