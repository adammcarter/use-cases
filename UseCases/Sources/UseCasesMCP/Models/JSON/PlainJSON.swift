import MCP

/// A JSON value read exactly as written. The SDK's own ``Value`` reads a string that looks like a
/// data URL as binary data, which would change the text of a document that holds one; here a
/// string is always a string.
struct PlainJSON: Decodable {
  let value: Value

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      value = .null
    } else if let flag = try? container.decode(Bool.self) {
      value = .bool(flag)
    } else if let number = try? container.decode(Int.self) {
      value = .int(number)
    } else if let number = try? container.decode(Double.self) {
      value = .double(number)
    } else if let text = try? container.decode(String.self) {
      value = .string(text)
    } else if let items = try? container.decode([PlainJSON].self) {
      value = .array(
        items.map { item in
          item.value
        },
      )
    } else {
      let members = try container.decode([String: PlainJSON].self)
      value = .object(
        members.mapValues { member in
          member.value
        },
      )
    }
  }
}
