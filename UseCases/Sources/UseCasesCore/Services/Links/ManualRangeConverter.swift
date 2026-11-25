/// Cuts manual ranges from a file by the rules of chapter 08 and chapter 11 §89.5: columns count
/// Unicode code points from 1, a leading byte-order mark is not a column, an omitted start column
/// is the start of the line and an omitted end column takes the rest of the line and its break.
struct ManualRangeConverter: ManualRangeConverting {
  func place(
    _ range: ManualRange?,
    in content: ManualContent,
  ) throws(ManualRangeError) -> ManualPlacement {
    guard let range else {
      return wholeFile(content)
    }

    guard content.isText else {
      throw .notText
    }

    try requireLinesInside(
      range,
      content: content,
    )

    let start = try startOffset(
      of: range.start,
      in: content,
    )
    let end = try endOffset(
      of: range.end,
      in: content,
    )

    guard start <= end else {
      throw .startsAfterEnd
    }

    return ManualPlacement(
      lines: range.start.line ... range.end.line,
      span: start ..< end,
    )
  }

  /// Line 1 to the last line holding any bytes; an empty file is 1 to 1.
  private func wholeFile(_ content: ManualContent) -> ManualPlacement {
    ManualPlacement(
      lines: 1 ... max(content.lines.lineCount, 1),
      span: 0 ..< content.bytes.count,
    )
  }

  private func requireLinesInside(
    _ range: ManualRange,
    content: ManualContent,
  ) throws(ManualRangeError) {
    let lineCount = content.lines.lineCount

    for line in [range.start.line, range.end.line] where line > lineCount {
      throw .lineOutsideFile(
        line: line,
        lineCount: lineCount,
      )
    }
  }

  private func startOffset(
    of position: SourcePosition,
    in content: ManualContent,
  ) throws(ManualRangeError) -> Int {
    guard let column = position.column else {
      return content.lines.start(ofLine: position.line)
    }

    let text = textBytes(
      ofLine: position.line,
      in: content,
    )
    let length = scalarCount(
      in: text,
      of: content,
    )

    guard column <= length + 1 else {
      throw .startColumnOutsideLine(
        column: column,
        line: position.line,
        length: length,
      )
    }

    return offset(
      afterScalars: column - 1,
      in: text,
      of: content,
    )
  }

  private func endOffset(
    of position: SourcePosition,
    in content: ManualContent,
  ) throws(ManualRangeError) -> Int {
    guard let column = position.column else {
      return content.lines.end(ofLine: position.line)
    }

    let text = textBytes(
      ofLine: position.line,
      in: content,
    )
    let length = scalarCount(
      in: text,
      of: content,
    )

    guard column <= length else {
      throw .endColumnOutsideLine(
        column: column,
        line: position.line,
        length: length,
      )
    }

    return offset(
      afterScalars: column,
      in: text,
      of: content,
    )
  }

  /// The bytes columns are counted in: the line less its break, and on line 1 less the
  /// byte-order mark.
  private func textBytes(
    ofLine line: Int,
    in content: ManualContent,
  ) -> Range<Int> {
    var lower = content.lines.start(ofLine: line)

    if line == 1, content.hasByteOrderMark {
      lower += ManualContent.byteOrderMark.count
    }

    var upper = content.lines.end(ofLine: line)

    if upper > lower, content.bytes[upper - 1] == Self.lineFeed {
      upper -= 1
    }

    if upper > lower, content.bytes[upper - 1] == Self.carriageReturn {
      upper -= 1
    }

    return lower ..< max(lower, upper)
  }

  private func scalarCount(
    in text: Range<Int>,
    of content: ManualContent,
  ) -> Int {
    content.bytes[text].count { byte in
      Self.beginsScalar(byte)
    }
  }

  /// The offset just after the first `count` code points of the text.
  private func offset(
    afterScalars count: Int,
    in text: Range<Int>,
    of content: ManualContent,
  ) -> Int {
    var seen = 0

    for offset in text where Self.beginsScalar(content.bytes[offset]) {
      if seen == count {
        return offset
      }

      seen += 1
    }

    return text.upperBound
  }

  /// Whether this byte starts a code point, as every byte of strict UTF-8 but a continuation does.
  private static func beginsScalar(_ byte: UInt8) -> Bool {
    byte & 0xC0 != 0x80
  }

  private static let lineFeed: UInt8 = 0x0A
  private static let carriageReturn: UInt8 = 0x0D
}
