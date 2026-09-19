/// One physical line, located in both coordinate systems the marker code uses.
public struct PhysicalLine: Equatable, Sendable {
  /// The line's content, terminator excluded.
  public let text: String
  /// UTF-16 offset of the line's first code unit (JavaScript's `charStart`).
  public let codeUnitStart: Int
  /// UTF-16 offset just past the line terminator.
  public let codeUnitEnd: Int
  /// UTF-8 offset of the line's first byte.
  public let byteStart: Int
  /// UTF-8 offset just past the line terminator.
  public let byteEnd: Int

  /// The TypeScript `PhysicalLine`, in its key order.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("text", .string(text)),
      ("charStart", .number(Double(codeUnitStart))),
      ("charEnd", .number(Double(codeUnitEnd))),
      ("byteStart", .number(Double(byteStart))),
      ("byteEnd", .number(Double(byteEnd))),
    ]))
  }
}

/// Physical line splitting, shared by the explicit-span scanner (which reports
/// UTF-8 byte ranges, spec 4.4) and the Swift function recognizer (which lexes in
/// UTF-16 but also reports UTF-8 bytes, spec 9.3). Line `i` is the same physical
/// line in either coordinate system.
public enum PhysicalLines {
  /// LF, CR and CRLF all terminate a line. A terminator at the end of the
  /// content yields no trailing empty line; an interior blank line is kept.
  public static func split(_ content: String) -> [PhysicalLine] {
    split(codeUnits: Array(content.utf16))
  }

  static func split(codeUnits units: [UInt16]) -> [PhysicalLine] {
    var lines: [PhysicalLine] = []
    var position = 0
    var byteStart = 0
    while position < units.count {
      var end = position
      while end < units.count, units[end] != CodeUnits.lineFeed,
            units[end] != CodeUnits.carriageReturn
      {
        end += 1
      }
      let terminatorLength = terminatorLength(units, at: end)
      let text = CodeUnits.string(units[position ..< end])
      // CR and LF are ASCII, so terminator bytes equal terminator code units.
      let byteEnd = byteStart + text.utf8.count + terminatorLength
      lines.append(PhysicalLine(
        text: text,
        codeUnitStart: position,
        codeUnitEnd: end + terminatorLength,
        byteStart: byteStart,
        byteEnd: byteEnd,
      ))
      byteStart = byteEnd
      position = end + terminatorLength
    }
    return lines
  }

  /// The index of the line containing a UTF-16 position; nil past the end. A
  /// position on a terminator belongs to the line it terminates.
  public static func lineIndex(
    containingCodeUnit position: Int,
    in lines: [PhysicalLine],
  ) -> Int? {
    lines.firstIndex { line in
      position >= line.codeUnitStart && position < line.codeUnitEnd
    }
  }

  private static func terminatorLength(
    _ units: [UInt16],
    at index: Int,
  ) -> Int {
    guard index < units.count else {
      return 0
    }
    let isCRLF = units[index] == CodeUnits.carriageReturn
      && index + 1 < units.count
      && units[index + 1] == CodeUnits.lineFeed
    return isCRLF ? 2 : 1
  }
}
