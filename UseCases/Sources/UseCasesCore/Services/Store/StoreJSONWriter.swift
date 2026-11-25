/// Prints ``StoreJSONValue`` as the store's files are written.
public struct StoreJSONWriter: StoreJSONWriting {
  private static let hexDigits = Array("0123456789abcdef".utf8)

  /// Makes the writer.
  public init() {}

  /// The value with no white space at all.
  public func compact(_ value: StoreJSONValue) -> [UInt8] {
    var output: [UInt8] = []

    append(
      value,
      to: &output,
      indent: nil,
    )

    return output
  }

  /// The value with two spaces of indent and a line feed at the end.
  public func pretty(_ value: StoreJSONValue) -> [UInt8] {
    var output: [UInt8] = []

    append(
      value,
      to: &output,
      indent: 0,
    )
    output.append(0x0A)

    return output
  }

  /// `indent` is the depth of the value being written, or `nil` for no white space.
  private func append(
    _ value: StoreJSONValue,
    to output: inout [UInt8],
    indent: Int?,
  ) {
    switch value {
    case .null:
      output.append(contentsOf: Array("null".utf8))
    case let .boolean(flag):
      output.append(contentsOf: Array((flag ? "true" : "false").utf8))
    case let .integer(number):
      output.append(contentsOf: Array(String(number).utf8))
    case let .number(number):
      // A number JSON cannot hold is written as `null`, which the schema then refuses.
      output.append(contentsOf: Array((number.isFinite ? String(number) : "null").utf8))
    case let .string(text):
      appendString(
        text,
        to: &output,
      )
    case let .array(items):
      appendArray(
        items,
        to: &output,
        indent: indent,
      )
    case let .object(members):
      appendObject(
        members,
        to: &output,
        indent: indent,
      )
    }
  }

  private func appendArray(
    _ items: [StoreJSONValue],
    to output: inout [UInt8],
    indent: Int?,
  ) {
    guard !items.isEmpty else {
      output.append(contentsOf: Array("[]".utf8))
      return
    }

    output.append(UInt8(ascii: "["))

    for (index, item) in items.enumerated() {
      if index > 0 {
        output.append(UInt8(ascii: ","))
      }

      appendBreak(
        to: &output,
        depth: indent.map { $0 + 1 },
      )
      append(
        item,
        to: &output,
        indent: indent.map { $0 + 1 },
      )
    }

    appendBreak(
      to: &output,
      depth: indent,
    )
    output.append(UInt8(ascii: "]"))
  }

  private func appendObject(
    _ members: [StoreJSONMember],
    to output: inout [UInt8],
    indent: Int?,
  ) {
    guard !members.isEmpty else {
      output.append(contentsOf: Array("{}".utf8))
      return
    }

    let sorted = members.map { member in
      (bytes: Array(member.key.utf8), member: member)
    }
    .sorted { lhs, rhs in
      lhs.bytes.lexicographicallyPrecedes(rhs.bytes)
    }

    output.append(UInt8(ascii: "{"))

    for (index, entry) in sorted.enumerated() {
      if index > 0 {
        output.append(UInt8(ascii: ","))
      }

      appendBreak(
        to: &output,
        depth: indent.map { $0 + 1 },
      )
      appendString(
        entry.member.key,
        to: &output,
      )
      output.append(UInt8(ascii: ":"))
      if indent != nil {
        output.append(UInt8(ascii: " "))
      }

      append(
        entry.member.value,
        to: &output,
        indent: indent.map { $0 + 1 },
      )
    }

    appendBreak(
      to: &output,
      depth: indent,
    )
    output.append(UInt8(ascii: "}"))
  }

  /// A line feed and the indent of `depth`; nothing when the output has no white space.
  private func appendBreak(
    to output: inout [UInt8],
    depth: Int?,
  ) {
    guard let depth else {
      return
    }

    output.append(0x0A)
    output.append(contentsOf: [UInt8](repeating: UInt8(ascii: " "), count: depth * 2))
  }

  /// Quote and backslash get a backslash, every byte below 0x20 becomes `\u00xx` in lowercase
  /// hex, and everything else is the string's own UTF-8 bytes.
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
