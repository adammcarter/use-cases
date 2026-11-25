/// Where each line of a file begins, counting a line break as CR, LF or CRLF, each one break
/// (chapter 08 "The linked region").
///
/// The empty text after a final line break is not a line, and a leading UTF-8 byte-order mark is
/// part of the first line, so offsets count from the first byte of the file. Lines are counted
/// from 1.
struct LineIndex: Sendable {
  /// The offset of the first byte of each line, in order. Empty for an empty file.
  let lineStarts: [Int]

  /// How many bytes the file holds.
  let byteCount: Int

  /// Indexes the lines of a file's bytes.
  init(_ bytes: [UInt8]) {
    var starts: [Int] = bytes.isEmpty ? [] : [0]
    let count = bytes.count
    var offset = 0

    while offset < count {
      let byte = bytes[offset]
      let isLoneCarriageReturn =
        byte == Self.carriageReturn && !Self.isLineFeed(bytes, offset + 1)
      let isBreak = byte == Self.lineFeed || isLoneCarriageReturn

      if isBreak, offset + 1 < count {
        starts.append(offset + 1)
      }

      offset += 1
    }

    lineStarts = starts
    byteCount = count
  }

  /// How many lines the file has.
  var lineCount: Int {
    lineStarts.count
  }

  /// The line that holds the byte at `offset`; a line's break belongs to the line it ends.
  func line(containing offset: Int) -> Int {
    var low = 0
    var high = lineStarts.count

    while low < high {
      let middle = (low + high) / 2

      if lineStarts[middle] <= offset {
        low = middle + 1
      } else {
        high = middle
      }
    }

    return max(low, 1)
  }

  /// The offset where `line` begins; the end of the file for a line past the last.
  func start(ofLine line: Int) -> Int {
    guard line >= 1, line <= lineStarts.count else {
      return byteCount
    }

    return lineStarts[line - 1]
  }

  /// The offset just after `line` and its line break; the end of the file for the last line.
  func end(ofLine line: Int) -> Int {
    start(ofLine: line + 1)
  }

  private static let lineFeed: UInt8 = 0x0A
  private static let carriageReturn: UInt8 = 0x0D

  private static func isLineFeed(
    _ bytes: [UInt8],
    _ offset: Int,
  ) -> Bool {
    offset < bytes.count && bytes[offset] == lineFeed
  }
}
