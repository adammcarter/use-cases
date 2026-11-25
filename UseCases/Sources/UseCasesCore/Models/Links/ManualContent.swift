/// The bytes of a file a manual binding points at, with its lines.
struct ManualContent: Sendable {
  let bytes: [UInt8]
  let lines: LineIndex

  /// Whether the bytes are strict UTF-8: the only text a range can be cut from.
  let isText: Bool

  /// Whether the file starts with a UTF-8 byte-order mark, which is not a column.
  let hasByteOrderMark: Bool

  /// Indexes a file's bytes.
  init(bytes: [UInt8]) {
    self.bytes = bytes
    lines = LineIndex(bytes)
    isText = bytes.isStrictUTF8
    hasByteOrderMark = bytes.starts(with: Self.byteOrderMark)
  }

  /// The bytes of a UTF-8 byte-order mark.
  static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]
}
