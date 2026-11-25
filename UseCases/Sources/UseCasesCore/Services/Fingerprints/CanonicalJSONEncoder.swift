/// Canonical JSON written by hand, so nothing a general encoder might do (escape a slash, reorder
/// by locale, normalize a string, print a number its own way) can reach a fingerprint.
struct CanonicalJSONEncoder: CanonicalJSONEncoding {
  /// 2^53 - 1: the largest integer every implementation reads back exactly.
  static let largestInteger = 9_007_199_254_740_991

  private static let hexDigits = Array("0123456789abcdef".utf8)

  func encode(_ value: CanonicalValue) throws(CanonicalEncodingError) -> [UInt8] {
    var output: [UInt8] = []

    try append(
      value,
      to: &output,
    )

    return output
  }

  private func append(
    _ value: CanonicalValue,
    to output: inout [UInt8],
  ) throws(CanonicalEncodingError) {
    switch value {
    case .null:
      output.append(contentsOf: Array("null".utf8))
    case let .boolean(flag):
      output.append(contentsOf: Array((flag ? "true" : "false").utf8))
    case let .integer(number):
      guard (-Self.largestInteger ... Self.largestInteger).contains(number) else {
        throw .integerOutOfRange(number)
      }

      output.append(contentsOf: Array(String(number).utf8))
    case let .string(text):
      appendString(
        text,
        to: &output,
      )
    case let .array(items):
      try appendArray(
        items,
        to: &output,
      )
    case let .object(members):
      try appendObject(
        members,
        to: &output,
      )
    }
  }

  private func appendArray(
    _ items: [CanonicalValue],
    to output: inout [UInt8],
  ) throws(CanonicalEncodingError) {
    output.append(UInt8(ascii: "["))

    for (index, item) in items.enumerated() {
      if index > 0 {
        output.append(UInt8(ascii: ","))
      }

      try append(
        item,
        to: &output,
      )
    }

    output.append(UInt8(ascii: "]"))
  }

  private func appendObject(
    _ members: [CanonicalMember],
    to output: inout [UInt8],
  ) throws(CanonicalEncodingError) {
    let keyed = members.map { member in
      (bytes: Array(member.key.utf8), member: member)
    }
    .sorted { lhs, rhs in
      lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }

    output.append(UInt8(ascii: "{"))

    for (index, entry) in keyed.enumerated() {
      if index > 0 {
        guard entry.bytes != keyed[index - 1].bytes else {
          throw .duplicateKey(entry.member.key)
        }

        output.append(UInt8(ascii: ","))
      }

      appendString(
        entry.member.key,
        to: &output,
      )
      output.append(UInt8(ascii: ":"))

      try append(
        entry.member.value,
        to: &output,
      )
    }

    output.append(UInt8(ascii: "}"))
  }

  /// Quote and backslash get a backslash, every byte below 0x20 becomes `\u00xx` in lowercase
  /// hex, and everything else is the string's own UTF-8 bytes. A multibyte scalar never holds a
  /// byte below 0x80, so a byte walk cannot split one.
  private func appendString(
    _ text: String,
    to output: inout [UInt8],
  ) {
    output.append(UInt8(ascii: "\""))

    for byte in text.utf8 {
      switch byte {
      case UInt8(ascii: "\""), UInt8(ascii: "\\"):
        output.append(UInt8(ascii: "\\"))
        output.append(byte)
      case 0x00 ..< 0x20:
        output.append(contentsOf: Array("\\u00".utf8))
        output.append(Self.hexDigits[Int(byte >> 4)])
        output.append(Self.hexDigits[Int(byte & 0x0F)])
      default:
        output.append(byte)
      }
    }

    output.append(UInt8(ascii: "\""))
  }
}
