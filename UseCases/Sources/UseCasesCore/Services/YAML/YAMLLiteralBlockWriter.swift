/// Writes a literal block whose chomping indicator makes the last line breaks read back exactly,
/// and whose indentation indicator says so when the first line starts with a space or a tab.
struct YAMLLiteralBlockWriter: YAMLLiteralBlockWriting {
  /// How far in the lines of a block sit from the key or dash they belong to.
  static let indentation = 2

  func block(
    of text: String,
    parentIndent: Int,
  ) -> YAMLLiteralBlock? {
    guard
      text.unicodeScalars.contains("\n"),
      text.unicodeScalars.allSatisfy(Self.isHeldExactly),
      text.unicodeScalars.contains(where: Self.isVisible)
    else {
      return nil
    }

    var pieces = text.splitOnScalar("\n")
    var trailing = 0

    while pieces.last?.isEmpty == true {
      pieces.removeLast()
      trailing += 1
    }

    // The last line break is the end of the last line; each one beyond it is a blank line the
    // block keeps.
    let kept = Array(repeating: "", count: max(trailing - 1, 0))
    let padding = String(repeating: " ", count: parentIndent + Self.indentation)

    return YAMLLiteralBlock(
      header: header(
        firstLine: pieces.first { piece in
          !piece.isEmpty
        },
        trailingBreaks: trailing,
      ),
      lines: (pieces + kept).map { piece in
        piece.isEmpty ? "" : padding + piece
      },
    )
  }

  private func header(
    firstLine: String?,
    trailingBreaks: Int,
  ) -> String {
    // A first line that starts with a space would be read as more indented, and one that starts
    // with a tab is refused by older libyaml, unless the indentation is said.
    let indicator = firstLine?.unicodeScalars.first.map { scalar in
      scalar == " " || scalar == "\t"
    } == true ? String(Self.indentation) : ""

    switch trailingBreaks {
    case 0:
      return "|" + indicator + "-"
    case 1:
      return "|" + indicator
    default:
      return "|" + indicator + "+"
    }
  }

  private static func isHeldExactly(_ scalar: Unicode.Scalar) -> Bool {
    scalar == "\n" || scalar == "\t" || scalar.isYAMLPrintable
  }

  private static func isVisible(_ scalar: Unicode.Scalar) -> Bool {
    scalar != " " && scalar != "\n" && scalar != "\t"
  }
}
