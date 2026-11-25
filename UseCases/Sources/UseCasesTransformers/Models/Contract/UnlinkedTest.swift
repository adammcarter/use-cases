/// A test that ran inside no validation link.
struct UnlinkedTest: Encodable, Equatable, Sendable {
  let test: String
  let file: String?
  let line: Int?
  let status: ResultStatus

  private enum CodingKeys: String, CodingKey {
    case test
    case file
    case line
    case status
  }

  /// `file` and `line` are always written, as null when the test could not be located.
  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)

    try container.encode(
      test,
      forKey: .test,
    )
    try container.encode(
      file,
      forKey: .file,
    )
    try container.encode(
      line,
      forKey: .line,
    )
    try container.encode(
      status,
      forKey: .status,
    )
  }
}
