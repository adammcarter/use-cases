/// `doubleQuotedString` from the `yaml` package: `JSON.stringify` text,
/// re-escaped the YAML way, with a `\n` in a value long enough to be worth it
/// written as a real, indented line break.
struct DoubleQuotedScalar {
  private let json: [UInt16]
  private let context: UseCaseFileEmitter.Context
  private var output: [UInt16] = []
  private var start = 0
  private var index = 0

  static func text(
    _ text: [UInt16],
    _ context: UseCaseFileEmitter.Context,
  ) -> [UInt16] {
    var writer = DoubleQuotedScalar(json: JSONStringText.encode(text), context: context)
    return writer.write()
  }

  /// The original's single pass over the JSON text, index for index.
  private mutating func write() -> [UInt16] {
    while index < json.count {
      var current = json[index]
      if current == CodeUnits.space, unit(index + 1) == CodeUnits.reverseSolidus,
         unit(index + 2) == Self.letterN
      {
        output += slice(start, index) + [CodeUnits.reverseSolidus, CodeUnits.space]
        index += 1
        start = index
        current = CodeUnits.reverseSolidus
      }
      if current == CodeUnits.reverseSolidus {
        switch unit(index + 1) {
        case Self.letterU:
          writeUnicodeEscape()
        case Self.letterN:
          writeLineFeedEscape()
        default:
          index += 1
        }
      }
      index += 1
    }
    return start > 0 ? output + slice(start, json.count) : json
  }

  /// A `\uXXXX` escape, respelled the short YAML way where there is one.
  private mutating func writeUnicodeEscape() {
    output += slice(start, index)
    let code = Array(slice(index + 2, min(index + 6, json.count)))
    let respelled: [UInt16] = switch CodeUnits.string(code) {
    case "0000": Array("\\0".utf16)
    case "0007": Array("\\a".utf16)
    case "000b": Array("\\v".utf16)
    case "001b": Array("\\e".utf16)
    case "0085": Array("\\N".utf16)
    case "00a0": Array("\\_".utf16)
    case "2028": Array("\\L".utf16)
    case "2029": Array("\\P".utf16)
    default:
      code.starts(with: [0x30, 0x30])
        ? Array("\\x".utf16) + code.dropFirst(2)
        : Array(slice(index, min(index + 6, json.count)))
    }
    output += respelled
    index += 5
    start = index + 1
  }

  /// A `\n` escape: kept as written in a key, before the closing quote, or in
  /// a value under 40 code units; otherwise a real line break (doubled, since
  /// folding eats one), the indent, and `\` before a leading space.
  private mutating func writeLineFeedEscape() {
    if context.isImplicitKey || unit(index + 2) == CodeUnits.quotationMark || json.count < 40 {
      index += 1
      return
    }
    output += slice(start, index) + [CodeUnits.lineFeed, CodeUnits.lineFeed]
    while unit(index + 2) == CodeUnits.reverseSolidus, unit(index + 3) == Self.letterN,
          unit(index + 4) != CodeUnits.quotationMark
    {
      output.append(CodeUnits.lineFeed)
      index += 2
    }
    output += context.indent
    if unit(index + 2) == CodeUnits.space {
      output.append(CodeUnits.reverseSolidus)
    }
    index += 1
    start = index + 1
  }

  private func unit(_ position: Int) -> UInt16? {
    position < json.count ? json[position] : nil
  }

  /// `json.slice(from, upTo)`: empty when the range is.
  private func slice(
    _ from: Int,
    _ upTo: Int,
  ) -> ArraySlice<UInt16> {
    from < upTo ? json[from ..< upTo] : []
  }

  private static let letterU: UInt16 = 0x75
  private static let letterN: UInt16 = 0x6E
}
