/// What one physical source line is, as far as the marker grammar goes.
public enum MarkerLineParse: Equatable, Sendable {
  /// Not a marker: an ordinary line or comment the scanner ignores.
  case none
  /// A start marker. `explicit` is true for `begin <slug>`, false for a bare slug.
  case start(slug: String, explicit: Bool, column: Int)
  case end(slug: String, column: Int)
  case ignoreBegin(column: Int)
  case ignoreEnd(column: Int)
  /// The marker token matched but the payload is not grammatical.
  case invalid(code: MarkerErrorCode, message: String, column: Int, slug: String?)

  /// The TypeScript result object, in its key order. `slug` is absent, not
  /// null, on an invalid parse that has none.
  var jsonValue: JSONValue {
    switch self {
    case .none:
      .object(JSONObject([("kind", .string("none"))]))
    case let .start(slug, explicit, column):
      .object(JSONObject([
        ("kind", .string("start")),
        ("slug", .string(slug)),
        ("explicit", .bool(explicit)),
        ("column", .number(Double(column))),
      ]))
    case let .end(slug, column):
      .object(JSONObject([
        ("kind", .string("end")),
        ("slug", .string(slug)),
        ("column", .number(Double(column))),
      ]))
    case let .ignoreBegin(column):
      .object(JSONObject([("kind", .string("ignore-begin")), ("column", .number(Double(column)))]))
    case let .ignoreEnd(column):
      .object(JSONObject([("kind", .string("ignore-end")), ("column", .number(Double(column)))]))
    case let .invalid(code, message, column, slug):
      Self.invalidJSON(code: code, message: message, column: column, slug: slug)
    }
  }

  private static func invalidJSON(
    code: MarkerErrorCode,
    message: String,
    column: Int,
    slug: String?,
  ) -> JSONValue {
    var object = JSONObject([
      ("kind", .string("invalid")),
      ("code", .string(code.rawValue)),
      ("message", .string(message)),
      ("column", .number(Double(column))),
    ])
    if let slug {
      object["slug"] = .string(slug)
    }
    return .object(object)
  }
}
