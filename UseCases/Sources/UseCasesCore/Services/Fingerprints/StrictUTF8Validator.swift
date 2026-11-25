/// Whether bytes are strict UTF-8 (no overlong form, surrogate, out-of-range scalar or truncated
/// sequence), taken a chunk at a time: the answer is the one ``Array/isStrictUTF8`` gives for all
/// the bytes at once, wherever the chunks are cut.
struct StrictUTF8Validator {
  private var isValid = true

  /// The start of a sequence that the last chunk ended inside.
  private var pending: [UInt8] = []

  /// Whether everything taken in so far is strict UTF-8.
  var isStrictUTF8: Bool {
    isValid && pending.isEmpty
  }

  mutating func add(_ chunk: [UInt8]) {
    guard isValid else {
      return
    }

    let bytes = pending + chunk
    let split = Self.startOfIncompleteSequence(in: bytes)

    pending = Array(bytes[split...])

    if !Array(bytes[..<split]).isStrictUTF8 {
      isValid = false
    }
  }

  /// Where the bytes end inside a sequence that its leading byte says is longer than what is
  /// there; the end of the bytes when they do not.
  private static func startOfIncompleteSequence(in bytes: [UInt8]) -> Int {
    var index = bytes.count

    for seen in 1 ... 3 {
      guard index > 0 else {
        break
      }

      index -= 1

      let byte = bytes[index]

      // A continuation byte belongs to a leading byte before it.
      guard byte & 0xC0 != 0x80 else {
        continue
      }

      let length =
        switch byte {
        case 0xF0...: 4
        case 0xE0...: 3
        case 0xC0...: 2
        default: 1
        }

      return length > seen ? index : bytes.count
    }

    return bytes.count
  }
}
