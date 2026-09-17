/// Where a marker sits: 1-based line and column.
public struct MarkerPosition: Equatable, Sendable {
  public let line: Int
  public let column: Int

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("line", .number(Double(line))),
      ("column", .number(Double(column))),
    ]))
  }
}

/// How a binding's span was bounded.
public enum BindingExtentKind: String, Equatable, Sendable {
  case explicit
  case swiftFunctionInferred = "swift_func_inferred"
}

/// Which kind of proof bounded the span, and for an inferred one, what symbol.
public enum BindingDiagnostic: Equatable, Sendable {
  case explicit
  case inferredSwiftFunction(symbolName: String)

  var jsonValue: JSONValue {
    switch self {
    case .explicit:
      .object(JSONObject([("inferred", .bool(false))]))
    case let .inferredSwiftFunction(symbolName):
      .object(JSONObject([
        ("symbol_kind", .string("swift_func")),
        ("symbol_name", .string(symbolName)),
        ("inferred", .bool(true)),
      ]))
    }
  }
}

/// A binding's span: lines, UTF-8 byte range and canonical hash.
public struct BindingSpan: Equatable, Sendable {
  public let startLine: Int
  /// For an empty explicit span this is `startLine - 1`, the TypeScript's
  /// empty-span signal.
  public let endLine: Int
  public let startByte: Int
  public let endByte: Int
  public let sha256: String

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("start_line", .number(Double(startLine))),
      ("end_line", .number(Double(endLine))),
      ("start_byte", .number(Double(startByte))),
      ("end_byte", .number(Double(endByte))),
      ("sha256", .string(sha256)),
    ]))
  }
}

/// The current binding record (spec section 4.4), explicit or inferred.
public struct CurrentBindingRecord: Equatable, Sendable {
  public let bindingSlug: String
  public let rowIdentifier: String
  public let suffix: String?
  public let filePath: String
  public let commentPrefix: String
  public let extentKind: BindingExtentKind
  public let recognizerIdentifier: String
  public let spanCanonicalizerIdentifier: String
  public let startMarker: MarkerPosition
  public let endMarker: MarkerPosition?
  public let span: BindingSpan
  public let diagnostic: BindingDiagnostic

  /// The TypeScript record, in its key order.
  var jsonValue: JSONValue {
    .object(JSONObject([
      ("binding_slug", .string(bindingSlug)),
      ("row_id", .string(rowIdentifier)),
      ("suffix", suffix.map(JSONValue.string) ?? .null),
      ("file_path", .string(filePath)),
      ("comment_prefix", .string(commentPrefix)),
      ("extent_kind", .string(extentKind.rawValue)),
      ("recognizer_id", .string(recognizerIdentifier)),
      ("span_canon_id", .string(spanCanonicalizerIdentifier)),
      ("start_marker", startMarker.jsonValue),
      ("end_marker", endMarker?.jsonValue ?? .null),
      ("span", span.jsonValue),
      ("diagnostic", diagnostic.jsonValue),
    ]))
  }
}
