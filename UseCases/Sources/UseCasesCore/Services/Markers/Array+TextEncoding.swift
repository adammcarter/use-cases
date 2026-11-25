extension [UInt8] {
  /// Whether the bytes are strict UTF-8: no overlong form, surrogate, out-of-range scalar or
  /// truncated sequence.
  var isStrictUTF8: Bool {
    var decoder = UTF8()
    var iterator = makeIterator()

    while true {
      switch decoder.decode(&iterator) {
      case .scalarValue:
        continue
      case .emptyInput:
        return true
      case .error:
        return false
      }
    }
  }

  /// Whether the file starts with a UTF-16 or UTF-32 byte-order mark: `FF FE` (UTF-16 or UTF-32
  /// little-endian), `FE FF` (UTF-16 big-endian) or `00 00 FE FF` (UTF-32 big-endian).
  var startsWithWideByteOrderMark: Bool {
    let head = Array(prefix(4))

    if head.starts(with: [0xFF, 0xFE]) || head.starts(with: [0xFE, 0xFF]) {
      return true
    }

    return head == [0x00, 0x00, 0xFE, 0xFF]
  }
}
