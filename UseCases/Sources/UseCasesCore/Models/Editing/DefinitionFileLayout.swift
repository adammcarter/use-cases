/// A definition file read as lines, and where each of its use cases is written. A use case runs
/// from its `- ` to the next one. Blank lines after it go with it, unless they are the text of a
/// block that keeps them, and a comment on lines of its own directly above the next use case
/// belongs to that next one.
struct DefinitionFileLayout: Equatable, Sendable {
  /// One use case, as lines of the file. Every index counts lines from 0.
  struct Item: Equatable, Sendable {
    /// The first line of the comments directly above the use case; the use case's own first line
    /// when there are none.
    let attachedStart: Int

    /// The line with the dash.
    let start: Int

    /// After the last line that is the use case's.
    let ownEnd: Int

    /// After the blank lines that follow it.
    let gapEnd: Int

    /// Whether the blank lines after its last field are the text of a block that keeps them.
    let keepsBlankLines: Bool

    /// The comments directly above the use case.
    let leadingComments: [FileComment]

    /// The comments inside the use case.
    let innerComments: [FileComment]

    /// How many spaces the use case's own fields are indented; `nil` when they are not written
    /// as a block mapping a line can be found in, as `- { id: x }` is not.
    let fieldIndent: Int?

    /// The lines of the use case's `approved` field, its key line to its last line; `nil` when
    /// it has none.
    let approved: Range<Int>?

    /// After the last line of the use case's text: the blank lines that follow are part of it
    /// when its last block keeps them.
    var contentEnd: Int {
      keepsBlankLines ? gapEnd : ownEnd
    }

    /// How many blank lines set it apart from what follows; none when they are its text.
    var gap: Int {
      keepsBlankLines ? 0 : gapEnd - ownEnd
    }
  }

  let lines: [String]

  /// What ends a line: `\n`, or `\r\n` when every line of the file ends that way.
  let lineBreak: String
  let endsWithLineBreak: Bool

  /// How many spaces the dash of a use case is indented.
  let itemIndent: Int
  let items: [Item]

  /// The comments of every line of the file.
  let comments: [FileComment]

  /// Reads the file.
  ///
  /// - Parameter text: The file as it is on disk.
  /// - Throws: ``DefinitionFileLayoutError`` when the use cases are not written one to a `- `
  ///   under a plain `use_cases:` key, which is the only layout a line can be found by.
  init(text: String) throws(DefinitionFileLayoutError) {
    let split = Self.split(text)
    let lines = split.lines
    var scanner = YAMLLineScanner()
    // A byte order mark starts the file and is no part of its first line.
    let scanned = lines.enumerated().map { number, line in
      scanner.scan(number == 0 ? line.droppingByteOrderMark() : line)
    }

    guard
      let header = scanned.indices.first(where: { index in
        Self.isUseCasesKey(scanned[index])
      })
    else {
      throw .notFound
    }

    guard !Self.hasValue(scanned[header]) else {
      throw .notAList
    }

    let file = ScannedFile(
      lines: lines,
      scanned: scanned,
    )
    let starts = try Self.starts(
      after: header,
      in: file,
    )

    self.lines = lines
    lineBreak = split.lineBreak
    endsWithLineBreak = split.endsWithLineBreak
    itemIndent = starts.indent
    comments = Self.comments(
      of: scanned,
      lines: lines,
      in: 0 ..< lines.count,
    )
    items = Self.items(
      after: header,
      starting: starts,
      in: file,
    )
  }

  /// The comments in some of the lines, own-line and trailing alike, none from the text of a
  /// block.
  static func comments(
    of scanned: [ScannedLine],
    lines: [String],
    in range: Range<Int>,
  ) -> [FileComment] {
    range.compactMap { index in
      switch scanned[index].kind {
      case .comment:
        FileComment(
          line: index + 1,
          text: lines[index].trimmingSpaces(),
        )
      case .content:
        scanned[index].trailingComment.map { text in
          FileComment(
            line: index + 1,
            text: text,
          )
        }
      case .blank:
        nil
      }
    }
  }

  /// The text of the lines: each ends with the file's own line break, the last one only if the
  /// file's did.
  func text(of lines: [String]) -> String {
    guard !lines.isEmpty else {
      return ""
    }

    return lines.joined(separator: lineBreak) + (endsWithLineBreak ? lineBreak : "")
  }

  private static func split(_ text: String) -> SplitText {
    var lines = text.splitOnScalar("\n")
    let endsWithLineBreak = lines.count > 1 && lines.last == ""

    if endsWithLineBreak {
      lines.removeLast()
    }

    let broken = endsWithLineBreak ? lines : Array(lines.dropLast())
    let usesCarriageReturns = !broken.isEmpty
      && broken.allSatisfy { line in
        line.unicodeScalars.last == "\r"
      }

    guard usesCarriageReturns else {
      return SplitText(
        lines: lines,
        lineBreak: "\n",
        endsWithLineBreak: endsWithLineBreak,
      )
    }

    return SplitText(
      lines: lines.map { line in
        line.unicodeScalars.last == "\r"
          ? String(String.UnicodeScalarView(line.unicodeScalars.dropLast()))
          : line
      },
      lineBreak: "\r\n",
      endsWithLineBreak: endsWithLineBreak,
    )
  }

  /// What follows the `use_cases` key and its colon on a line, when the line is that key at the
  /// start of a line. The key may be quoted, and a space may come before the colon.
  private static func valueOfUseCasesKey(_ scanned: ScannedLine) -> Substring? {
    guard scanned.kind == .content, scanned.indent == 0, !scanned.isBlockText else {
      return nil
    }

    for key in ["use_cases", "\"use_cases\"", "'use_cases'"] where scanned.code.hasPrefix(key) {
      let rest = scanned.code.dropFirst(key.count).drop { character in
        character == " " || character == "\t"
      }

      if rest.hasPrefix(":") {
        return rest.dropFirst()
      }
    }

    return nil
  }

  private static func isUseCasesKey(_ scanned: ScannedLine) -> Bool {
    valueOfUseCasesKey(scanned) != nil
  }

  /// Whether the key has a value of its own on its line, as `use_cases: []` does.
  private static func hasValue(_ scanned: ScannedLine) -> Bool {
    !(valueOfUseCasesKey(scanned) ?? "").allSatisfy { character in
      character == " " || character == "\t" || character == "\r"
    }
  }

  /// The lines of the dashes, how far they are indented, and where the list ends.
  private static func starts(
    after header: Int,
    in file: ScannedFile,
  ) throws(DefinitionFileLayoutError) -> ItemStarts {
    let scanned = file.scanned

    guard
      let first = ((header + 1) ..< scanned.count).first(where: { index in
        scanned[index].kind == .content
      }),
      isDash(scanned[first])
    else {
      throw .notAList
    }

    let indent = scanned[first].indent
    var starts: [Int] = []

    for index in first ..< scanned.count where scanned[index].kind == .content {
      let line = scanned[index]

      guard !line.isBlockText else {
        continue
      }

      if line.indent == indent, isDash(line) {
        starts.append(index)
      } else if line.indent <= indent {
        return ItemStarts(lines: starts, indent: indent, end: index)
      }
    }

    return ItemStarts(lines: starts, indent: indent, end: scanned.count)
  }

  static func isDash(_ scanned: ScannedLine) -> Bool {
    let text = scanned.code.dropFirst(scanned.indent)

    return text.trimmingSpaces() == "-" || text.hasPrefix("- ") || text.hasPrefix("-\t")
  }

  /// The last line that is a use case's own: not a blank line, and not a comment as far out as
  /// the dashes, which belongs to what follows.
  private static func lastLine(
    from start: Int,
    before end: Int,
    indent: Int,
    in scanned: [ScannedLine],
  ) -> Int {
    var last = end - 1

    while last > start {
      let line = scanned[last]

      if line.kind == .blank || (line.kind == .comment && line.indent <= indent) {
        last -= 1
      } else {
        break
      }
    }

    return last
  }

  /// The first line of each use case with the comments directly above it.
  private static func attachedStarts(
    after header: Int,
    starts: [Int],
    in scanned: [ScannedLine],
  ) -> [Int] {
    starts.enumerated().map { number, start in
      var first = start

      while first - 1 > (number == 0 ? header : starts[number - 1]),
            scanned[first - 1].kind == .comment
      {
        first -= 1
      }

      return first
    }
  }

  private static func items(
    after header: Int,
    starting itemStarts: ItemStarts,
    in file: ScannedFile,
  ) -> [Item] {
    let starts = itemStarts.lines
    let indent = itemStarts.indent
    let sequenceEnd = itemStarts.end
    let scanned = file.scanned
    let lines = file.lines

    let attached = attachedStarts(
      after: header,
      starts: starts,
      in: scanned,
    )

    return starts.indices.map { number in
      let end = number + 1 < starts.count ? attached[number + 1] : sequenceEnd
      let last = lastLine(
        from: starts[number],
        before: end,
        indent: indent,
        in: scanned,
      )

      let ownEnd = last + 1
      let keeps = scanned[last].keepsBlankLines
      var gapEnd = ownEnd

      while gapEnd < end, scanned[gapEnd].kind == .blank {
        gapEnd += 1
      }

      let fields = itemFields(
        of: starts[number] ..< ownEnd,
        in: scanned,
      )

      return Item(
        attachedStart: attached[number],
        start: starts[number],
        ownEnd: ownEnd,
        gapEnd: gapEnd,
        keepsBlankLines: keeps,
        leadingComments: comments(
          of: scanned,
          lines: lines,
          in: attached[number] ..< starts[number],
        ),
        innerComments: comments(
          of: scanned,
          lines: lines,
          in: starts[number] ..< ownEnd,
        ),
        fieldIndent: fields?.indent,
        approved: fields?.approved,
      )
    }
  }
}

private extension StringProtocol {
  /// Without the spaces and tabs around it, and the carriage return a mixed file may end a line
  /// with.
  func trimmingSpaces() -> String {
    var scalars = Array(unicodeScalars)

    while let last = scalars.last, last == " " || last == "\t" || last == "\r" {
      scalars.removeLast()
    }

    return String(String.UnicodeScalarView(scalars.drop { $0 == " " || $0 == "\t" }))
  }

  func droppingByteOrderMark() -> String {
    unicodeScalars.first == "\u{FEFF}"
      ? String(String.UnicodeScalarView(unicodeScalars.dropFirst()))
      : String(self)
  }
}

/// The lines of a file with what the scanner made of each.
private struct ScannedFile {
  let lines: [String]
  let scanned: [ScannedLine]
}

/// A file cut into lines, and how it ends its lines.
private struct SplitText {
  let lines: [String]
  let lineBreak: String
  let endsWithLineBreak: Bool
}

/// Where the dashes of the use cases are, how far they are indented, and where the list ends.
private struct ItemStarts {
  let lines: [Int]
  let indent: Int
  let end: Int
}
