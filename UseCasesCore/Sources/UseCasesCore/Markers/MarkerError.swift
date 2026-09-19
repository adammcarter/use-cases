/// A marker or span error code: a marker-pairing code or a Swift recognizer
/// (9.4) code. Every one denotes an INVALID condition.
public enum ScanErrorCode: Equatable, Sendable {
  case marker(MarkerErrorCode)
  case swiftFunction(SwiftFunctionErrorCode)

  /// The frozen wire string.
  public var rawValue: String {
    switch self {
    case let .marker(code):
      code.rawValue
    case let .swiftFunction(code):
      code.rawValue
    }
  }
}

/// One integrity problem found by the scanner, located in its file.
public struct MarkerError: Equatable, Sendable {
  public let code: ScanErrorCode
  public let message: String
  public let filePath: String
  /// 1-based.
  public let line: Int
  public let slug: String?

  /// `{ code, message, file_path, line, slug? }` — `slug` is absent, not null,
  /// when there is none.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("code", .string(code.rawValue)),
      ("message", .string(message)),
      ("file_path", .string(filePath)),
      ("line", .number(Double(line))),
    ])
    if let slug {
      object["slug"] = .string(slug)
    }
    return .object(object)
  }
}
