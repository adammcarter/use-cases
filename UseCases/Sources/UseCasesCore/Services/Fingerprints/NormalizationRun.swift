/// A normalization taken a chunk at a time (chapter 11 §12 to §18): the same bytes come out as
/// when the whole file is normalized at once, however the file is cut into chunks.
struct NormalizationRun {
  private static let carriageReturn: UInt8 = 0x0D
  private static let lineFeed: UInt8 = 0x0A

  private let normalizesLineEndings: Bool
  private let removesWhitespace: Bool

  /// A chunk ended with a carriage return, so a line feed that opens the next one is the same
  /// line ending.
  private var skipsLineFeed = false

  init(
    normalizesLineEndings: Bool,
    removesWhitespace: Bool,
  ) {
    self.normalizesLineEndings = normalizesLineEndings
    self.removesWhitespace = removesWhitespace
  }

  /// The next bytes, normalized. Only text is normalized: whether these bytes are text is not
  /// this run's to know.
  mutating func normalize(_ chunk: [UInt8]) -> [UInt8] {
    var output: [UInt8] = []

    output.reserveCapacity(chunk.count)

    for byte in chunk {
      if skipsLineFeed {
        skipsLineFeed = false

        if byte == Self.lineFeed {
          continue
        }
      }

      if removesWhitespace, byte.isBlankByte {
        continue
      }

      guard normalizesLineEndings, byte == Self.carriageReturn else {
        output.append(byte)
        continue
      }

      output.append(Self.lineFeed)
      skipsLineFeed = true
    }

    return output
  }
}
