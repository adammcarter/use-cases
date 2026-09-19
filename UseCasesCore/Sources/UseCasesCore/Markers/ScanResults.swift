/// One file to scan.
public struct ScanInput: Equatable, Sendable {
  public let filePath: String
  public let contents: String

  public init(
    filePath: String,
    contents: String,
  ) {
    self.filePath = filePath
    self.contents = contents
  }
}

/// The scan of one file. `commentPrefix` is nil when the file cannot carry
/// markers, in which case it was skipped.
public struct ScanFileResult: Equatable, Sendable {
  public let filePath: String
  public let commentPrefix: String?
  public let bindings: [CurrentBindingRecord]
  public let errors: [MarkerError]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("file_path", .string(filePath)),
      ("comment_prefix", commentPrefix.map(JSONValue.string) ?? .null),
      ("bindings", .array(bindings.map(\.jsonValue))),
      ("errors", .array(errors.map(\.jsonValue))),
    ]))
  }
}

/// The scan of many files, with bindings and errors flattened in file order.
public struct ScanResult: Equatable, Sendable {
  public let files: [ScanFileResult]
  public let bindings: [CurrentBindingRecord]
  public let errors: [MarkerError]

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("files", .array(files.map(\.jsonValue))),
      ("bindings", .array(bindings.map(\.jsonValue))),
      ("errors", .array(errors.map(\.jsonValue))),
    ]))
  }
}
