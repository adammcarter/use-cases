/// Where the fields of a use case are written.
struct ItemFields {
  let indent: Int
  let approved: Range<Int>?
}

extension DefinitionFileLayout {
  /// Where the fields of a use case are written, and its `approved` field among them.
  ///
  /// - Parameters:
  ///   - range: The use case's lines, from its dash.
  ///   - scanned: What the scanner made of every line of the file.
  /// - Returns: `nil` when the use case is not a block mapping, or has `approved` on its dash's
  ///   own line, where it cannot be told from the dash.
  static func itemFields(
    of range: Range<Int>,
    in scanned: [ScannedLine],
  ) -> ItemFields? {
    guard let indent = fieldIndent(of: range, in: scanned) else {
      return nil
    }

    let keys = range.filter { index in
      isKeyLine(
        index,
        of: range,
        indent: indent,
        in: scanned,
      )
    }

    guard
      let approved = keys.first(where: { index in
        namesApproved(
          scanned[index],
          at: index == range.lowerBound ? indent : scanned[index].indent,
          dash: index == range.lowerBound,
        )
      })
    else {
      return ItemFields(
        indent: indent,
        approved: nil,
      )
    }

    guard approved != range.lowerBound else {
      return nil
    }

    var end = keys.first { index in
      index > approved
    } ?? range.upperBound

    while end - 1 > approved, scanned[end - 1].kind != .content {
      end -= 1
    }

    return ItemFields(
      indent: indent,
      approved: approved ..< end,
    )
  }

  /// The column the first key of the use case is in, on the dash's line or the first line after.
  static func fieldIndent(
    of range: Range<Int>,
    in scanned: [ScannedLine],
  ) -> Int? {
    let dash = scanned[range.lowerBound]
    let afterDash = dash.code.dropFirst(dash.indent + 1)
    let spaces = afterDash.prefix(while: isSpace)
    let rest = afterDash.dropFirst(spaces.count)

    if rest.hasPrefix("{") || rest.hasPrefix("[") {
      return nil
    }

    if !rest.isEmpty {
      return dash.indent + 1 + spaces.count
    }

    return range.dropFirst().first { index in
      scanned[index].kind == .content && !scanned[index].isBlockText
    }.map { index in
      scanned[index].indent
    }
  }

  /// Whether a line begins a field of the use case: its dash's line, or a line in the column of
  /// the fields that is not an item of a list written in that column.
  static func isKeyLine(
    _ index: Int,
    of range: Range<Int>,
    indent: Int,
    in scanned: [ScannedLine],
  ) -> Bool {
    if index == range.lowerBound {
      return true
    }

    let line = scanned[index]

    return line.kind == .content && !line.isBlockText && line.indent == indent
      && !isDash(line)
  }

  static func namesApproved(
    _ line: ScannedLine,
    at column: Int,
    dash: Bool,
  ) -> Bool {
    let text = dash
      ? line.code.dropFirst(line.indent + 1).drop(while: isSpace)
      : line.code.dropFirst(column)

    for key in ["approved", "\"approved\"", "'approved'"] where text.hasPrefix(key) {
      let rest = text.dropFirst(key.count).drop(while: isSpace)

      if rest.hasPrefix(":") {
        return true
      }
    }

    return false
  }

  private static func isSpace(_ character: Character) -> Bool {
    character == " " || character == "\t"
  }
}
