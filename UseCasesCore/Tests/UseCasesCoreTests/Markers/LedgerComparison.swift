@testable import UseCasesCore

/// Wire comparison for ledger results, with one deliberate allowance.
///
/// A JSON_PARSE_ERROR message ends with the JavaScript engine's own parser
/// text (`Expected property name or '}' in JSON at position 1 …`), which is
/// V8's and not reproducible. Everything up to it — `line N is not valid
/// JSON: ` — and the code and line are compared exactly; only that engine
/// suffix is cut, on both sides.
enum LedgerComparison {
  static let parseErrorMarker = " is not valid JSON: "

  static func normalized(_ value: JSONValue) -> JSONValue {
    switch value {
    case let .array(elements):
      return .array(elements.map(normalized))
    case let .object(object):
      var copy = JSONObject()
      for pair in object.pairs {
        copy[pair.key] = normalized(pair.value)
      }
      if copy["code"]?.stringValue == "JSON_PARSE_ERROR",
         let message = copy["message"]?.stringValue,
         let range = message.range(of: parseErrorMarker)
      {
        copy["message"] = .string(String(message[..<range.upperBound]) + "<engine message>")
      }
      return .object(copy)
    default:
      return value
    }
  }

  static func wire(_ value: JSONValue) -> String {
    JSONWriter.encode(normalized(value))
  }
}
