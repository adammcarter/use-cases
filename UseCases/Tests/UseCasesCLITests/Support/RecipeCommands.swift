import Foundation
@testable import UseCasesCLI

/// The `use-cases` commands a recipe document writes, read the way a shell reads a command: its
/// words, with quotes honoured, up to a pipe, a semicolon, an ampersand, a backtick, a closing
/// parenthesis nothing opened, a comment or the end of the line.
enum RecipeCommands {
  /// The arguments of each command in the text, the command's own name first. A CI variable, a
  /// `${{ … }}` expression and a `<placeholder>` each stand for one word.
  static func arguments(in text: String) throws -> [[String]] {
    let placeholders = try Regex(#""\$\{?[A-Z_]+\}?"|\$\{\{[^}]*\}\}|\$[A-Z_]+|<[^>]+>"#)
    let names = DesignedCommand.allCases.map(\.rawValue).joined(separator: "|")
    let command = try Regex("use-cases (" + names + #")\b"#)
    var inTextBlock = false
    var found: [[String]] = []

    for var line in text.components(separatedBy: "\n") {
      if line.hasPrefix("```") {
        inTextBlock = line == "```text"
        continue
      }

      if inTextBlock {
        line = cut(line)
      }

      line = line.replacing(placeholders, with: "x")

      for match in line.matches(of: command) {
        let name = String(match.output[1].substring ?? "")

        found.append([name] + words(of: line[match.range.upperBound...]))
      }
    }

    return found
  }

  /// A line of a text block runs on into a description or an arrow after a gap of two spaces.
  private static func cut(_ line: String) -> String {
    let indent = line.prefix { $0 == " " }.count
    var text = String(line.dropFirst(indent))

    for gap in ["  ", "→", "─"] {
      if let range = text.range(of: gap) {
        text = String(text[..<range.lowerBound])
      }
    }

    return String(line.prefix(indent)) + text
  }

  /// The words of a command line from here on, until it ends.
  private static func words(of rest: Substring) -> [String] {
    var splitter = WordSplitter()

    for character in rest where !splitter.take(character) {
      break
    }

    splitter.finish()

    return splitter.words
  }
}

/// Splits a command line into words as a shell does: quotes keep a space in a word, and an
/// unquoted pipe, semicolon, ampersand, backtick, redirection or comment, or a closing
/// parenthesis nothing opened, ends the command. A word that ends in a comma is prose, and ends
/// the command; so does the name of the program again.
private struct WordSplitter {
  private(set) var words: [String] = []
  private var word = ""
  private var hasWord = false
  private var quote: Character?
  private var depth = 0
  private var isDone = false

  /// Reads one character; `false` when the command has ended.
  mutating func take(_ character: Character) -> Bool {
    if let open = quote {
      if character == open {
        quote = nil
      } else {
        word.append(character)
      }

      return true
    }

    switch character {
    case "'", "\"":
      quote = character
      hasWord = true
    case " ":
      finish()
    case "|", ";", "&", "`", ">", "<", "#":
      isDone = true
      finish()
    case ")" where depth == 0:
      isDone = true
      finish()
    default:
      depth += character == "(" ? 1 : character == ")" ? -1 : 0
      word.append(character)
      hasWord = true
    }

    return !isDone
  }

  /// Ends the word being read, if there is one.
  mutating func finish() {
    defer {
      word = ""
      hasWord = false
    }

    guard hasWord else {
      return
    }

    if word == "use-cases" {
      isDone = true
    } else if word.hasSuffix(",") {
      words.append(String(word.dropLast()))
      isDone = true
    } else {
      words.append(word)
    }
  }
}
