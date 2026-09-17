import Foundation

/// Writes a ``JSONValue`` as wire JSON: no spaces, `JSON.stringify` escaping,
/// and members in the order the document carries them.
///
/// Foundation's `JSONEncoder` cannot be used for anything the wire contract
/// covers: it builds a dictionary, so the key order an `encode(to:)` asks for is
/// lost. The envelope's eight keys are contract (ADR 0007 decision 8), so the
/// bytes are produced here instead.
public enum JSONWriter {
  /// `sortingKeys` gives the canonical form the semantic hash is taken over;
  /// document order gives the wire form.
  public static func encode(
    _ value: JSONValue,
    sortingKeys: Bool = false,
  ) -> String {
    switch value {
    case .null:
      "null"
    case let .bool(flag):
      flag ? "true" : "false"
    case let .number(number):
      JavaScriptNumber.text(number)
    case let .string(text):
      encodeString(text)
    case let .array(values):
      encodeArray(values, sortingKeys: sortingKeys)
    case let .object(object):
      encodeObject(object, sortingKeys: sortingKeys)
    }
  }

  private static func encodeArray(
    _ values: [JSONValue],
    sortingKeys: Bool,
  ) -> String {
    var members: [String] = []
    for value in values {
      members.append(encode(value, sortingKeys: sortingKeys))
    }
    return "[" + members.joined(separator: ",") + "]"
  }

  private static func encodeObject(
    _ object: JSONObject,
    sortingKeys: Bool,
  ) -> String {
    let pairs = sortingKeys ? sortedByLocale(object.pairs) : object.pairs
    var members: [String] = []
    for pair in pairs {
      let key = encodeString(pair.key)
      members.append("\(key):\(encode(pair.value, sortingKeys: sortingKeys))")
    }
    return "{"
      + members.joined(separator: ",")
      + "}"
  }

  /// Sorted the way JavaScript's `String.prototype.localeCompare` sorts:
  /// punctuation before letters, lowercase before uppercase.
  private static func sortedByLocale(
    _ pairs: [(key: String, value: JSONValue)],
  ) -> [(key: String, value: JSONValue)] {
    pairs.sorted { left, right in
      let order = left.key.compare(
        right.key,
        options: [],
        range: nil,
        locale: Locale(identifier: "en_US"),
      )
      return order == .orderedAscending
    }
  }

  /// `JSON.stringify`'s string escaping: the seven short escapes, `\u00xx` for
  /// the remaining control characters, and everything else left as it is.
  private static func encodeString(_ text: String) -> String {
    var encoded = "\""
    for scalar in text.unicodeScalars {
      switch scalar {
      case "\"":
        encoded += "\\\""
      case "\\":
        encoded += "\\\\"
      case "\n":
        encoded += "\\n"
      case "\r":
        encoded += "\\r"
      case "\t":
        encoded += "\\t"
      case Unicode.Scalar(0x08):
        encoded += "\\b"
      case Unicode.Scalar(0x0C):
        encoded += "\\f"
      default:
        if scalar.value < 0x20 {
          encoded += String(format: "\\u%04x", scalar.value)
        } else {
          encoded.unicodeScalars.append(scalar)
        }
      }
    }
    return encoded + "\""
  }
}
