/// The proven extent of an inferred Swift function span.
public struct SwiftFunctionSpan: Equatable, Sendable {
  /// 1-based: the first attached attribute, modifier or `func` line.
  public let startLine: Int
  /// 1-based: the line of the body's closing brace.
  public let endLine: Int
  /// UTF-8 offset of the first byte of `startLine`.
  public let startByte: Int
  /// UTF-8 offset just past `endLine`'s terminator, or the end of the file.
  public let endByte: Int
}

/// What the recognizer proved, or the section 9.4 reason it refused to guess.
public enum SwiftFunctionRecognition: Equatable, Sendable {
  case recognized(span: SwiftFunctionSpan, symbolName: String, bodyLines: [String])
  /// `line` is the 1-based marker line.
  case failed(code: SwiftFunctionErrorCode, message: String, line: Int)

  /// The TypeScript result object, in its key order.
  var jsonValue: JSONValue {
    switch self {
    case let .recognized(span, symbolName, bodyLines):
      .object(JSONObject([
        ("ok", .bool(true)),
        ("span", .object(JSONObject([
          ("start_line", .number(Double(span.startLine))),
          ("end_line", .number(Double(span.endLine))),
          ("start_byte", .number(Double(span.startByte))),
          ("end_byte", .number(Double(span.endByte))),
        ]))),
        ("symbol_name", .string(symbolName)),
        ("body_lines", .array(bodyLines.map(JSONValue.string))),
      ]))
    case let .failed(code, message, line):
      .object(JSONObject([
        ("ok", .bool(false)),
        ("code", .string(code.rawValue)),
        ("message", .string(message)),
        ("line", .number(Double(line))),
      ]))
    }
  }
}
