/// Reads the lines of a YAML file one after another and says what each is made of, keeping what a
/// line needs from the ones before it: whether it is text of a block (`|` or `>`), which no
/// comment can be in, whether a quoted text is still open, and how deep in a flow collection
/// (`[...]` or `{...}`) the line is.
struct YAMLLineScanner {
  /// The indent of the line a block's text hangs from; its text is indented more.
  private var blockParent: Int?

  /// The indent of the block's first line of text, which every line of its text is indented as
  /// much as: the first line that is indented less ends the block. `nil` until that line comes.
  private var blockTextIndent: Int?
  private var blockExplicitIndent: Int?
  private var blockKeepsBlankLines = false
  private var openQuote: Unicode.Scalar?
  private var flowDepth = 0

  /// Reads the next line of the file.
  mutating func scan(_ line: String) -> ScannedLine {
    let characters = Array(line.unicodeScalars)
    let indent = characters.prefix { character in
      character == " "
    }.count
    let isBlank = characters.dropFirst(indent).allSatisfy(Self.isWhitespace)

    if let line = readBlockLine(
      indent: indent,
      isBlank: isBlank,
    ) {
      return line
    }

    if openQuote == nil {
      if isBlank {
        return .blank(
          indent: indent,
          keepsBlankLines: false,
        )
      }

      if characters[indent] == "#" {
        return .comment(indent: indent)
      }
    }

    let code = readCode(of: characters)

    if openQuote == nil {
      openBlock(
        code: code.text,
        indent: indent,
      )
    }

    return ScannedLine(
      kind: .content,
      indent: indent,
      code: code.text,
      trailingComment: code.comment,
      isBlockText: false,
      keepsBlankLines: blockParent != nil && blockKeepsBlankLines,
    )
  }

  /// The text of a content line before its comment, and the comment. A quote that opens where a
  /// text starts hides what is inside it; one that is not closed stays open for the next line.
  private mutating func readCode(of characters: [Unicode.Scalar])
    -> (text: String, comment: String?)
  {
    var index = 0
    var quote = openQuote

    while index < characters.count {
      let character = characters[index]

      if let open = quote {
        if open == "\"", character == "\\" {
          index += 2
          continue
        }

        if character == open {
          if open == "'", index + 1 < characters.count, characters[index + 1] == "'" {
            index += 2
            continue
          }

          quote = nil
        }
      } else if character == "#", index == 0 || Self.isWhitespace(characters[index - 1]) {
        openQuote = nil

        return (
          Self.text(of: characters[..<index]),
          Self.text(of: characters[index...]).trimmingTrailingWhitespace(),
        )
      } else if let opened = opening(
        character,
        at: index,
        in: characters,
      ) {
        quote = opened
      }

      index += 1
    }

    openQuote = quote

    return (Self.text(of: characters[...]), nil)
  }

  /// A quote mark that starts a quoted text is the quote it opens. Brackets that start a flow
  /// collection, and the ones that end it, are counted.
  private mutating func opening(
    _ character: Unicode.Scalar,
    at index: Int,
    in characters: [Unicode.Scalar],
  ) -> Unicode.Scalar? {
    switch character {
    case "'", "\"":
      return startsValue(at: index, in: characters) ? character : nil
    case "[", "{":
      if startsValue(at: index, in: characters) {
        flowDepth += 1
      }
    case "]", "}":
      flowDepth = max(0, flowDepth - 1)
    default:
      break
    }

    return nil
  }

  /// Whether a value can start at `index`: it is the first thing on the line, or follows a key's
  /// colon or a list's dash after a space, or follows `[`, `{` or `,` inside a flow collection.
  /// Anywhere else a quote mark or a bracket is part of plain text, as in `Built in the '90s`.
  private func startsValue(
    at index: Int,
    in characters: [Unicode.Scalar],
  ) -> Bool {
    var before = index - 1

    while before >= 0, Self.isWhitespace(characters[before]) {
      before -= 1
    }

    guard before >= 0 else {
      return true
    }

    let spaced = before < index - 1

    switch characters[before] {
    case ":":
      return spaced || flowDepth > 0
    case "-":
      return spaced && characters[..<before].allSatisfy { $0 == " " || $0 == "-" }
    case "[", "{", ",":
      return flowDepth > 0
    default:
      return false
    }
  }

  /// The line, when it is in the open block: a blank line or text of it. A line that is neither
  /// ends the block, and is read as any other.
  private mutating func readBlockLine(
    indent: Int,
    isBlank: Bool,
  ) -> ScannedLine? {
    guard let parent = blockParent else {
      return nil
    }

    if isBlank {
      return .blank(
        indent: indent,
        keepsBlankLines: blockKeepsBlankLines,
      )
    }

    guard continuesBlock(atIndent: indent, parent: parent) else {
      endBlock()

      return nil
    }

    return .blockText(
      indent: indent,
      keepsBlankLines: blockKeepsBlankLines,
    )
  }

  private mutating func endBlock() {
    blockParent = nil
    blockTextIndent = nil
    blockExplicitIndent = nil
    blockKeepsBlankLines = false
  }

  /// Whether a line indented this much is text of the open block. The block's text is indented
  /// as much as its first line of it; a line indented less is no longer part of it.
  private mutating func continuesBlock(
    atIndent indent: Int,
    parent: Int,
  ) -> Bool {
    if let textIndent = blockTextIndent {
      return indent >= textIndent
    }

    let first = blockExplicitIndent.map { parent + $0 } ?? indent

    guard indent > parent, indent >= first else {
      return false
    }

    blockTextIndent = first

    return true
  }

  /// A line that ends with `|` or `>` after a key or a dash opens a block of text.
  private mutating func openBlock(
    code: String,
    indent: Int,
  ) {
    let trimmed = code.trimmingTrailingWhitespace()
    let words = trimmed.split(separator: " ")

    guard let last = words.last, Self.isBlockIndicator(last) else {
      return
    }

    var position = indent
    var rest = Substring(trimmed.dropFirst(indent))
    var dashColumn: Int?

    while rest.hasPrefix("- ") {
      dashColumn = position
      let spaces = rest.dropFirst().prefix { character in
        character == " "
      }.count
      position += 1 + spaces
      rest = rest.dropFirst(1 + spaces)
    }

    let parent: Int

    if rest == last {
      // A block straight after a dash hangs from the dash.
      guard let dashColumn else {
        return
      }

      parent = dashColumn
    } else {
      guard rest.dropLast(last.count).trimmingTrailingWhitespace().hasSuffix(":") else {
        return
      }

      parent = position
    }

    blockParent = parent
    blockTextIndent = nil
    blockExplicitIndent = last.compactMap(\.wholeNumberValue).first
    blockKeepsBlankLines = last.contains("+")
  }

  private static func isBlockIndicator(_ word: Substring) -> Bool {
    guard let first = word.first, first == "|" || first == ">" else {
      return false
    }

    let modifiers = word.dropFirst()

    return modifiers.count <= 2
      && modifiers.allSatisfy { character in
        character == "+" || character == "-" || ("1" ... "9").contains(character)
      }
  }

  private static func text(of scalars: ArraySlice<Unicode.Scalar>) -> String {
    String(String.UnicodeScalarView(scalars))
  }

  private static func isWhitespace(_ character: Unicode.Scalar) -> Bool {
    character == " " || character == "\t" || character == "\r"
  }
}

private extension StringProtocol {
  func trimmingTrailingWhitespace() -> String {
    var scalars = Array(unicodeScalars)

    while let last = scalars.last, last == " " || last == "\t" || last == "\r" {
      scalars.removeLast()
    }

    return String(String.UnicodeScalarView(scalars))
  }
}
