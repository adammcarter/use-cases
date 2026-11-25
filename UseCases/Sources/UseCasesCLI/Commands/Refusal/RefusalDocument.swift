import Foundation

/// The `--json` document of a refused request (`cli-error.schema.json`).
struct RefusalDocument: Encodable {
  /// The command, or `nil` when the command line names none.
  let command: String?
  let kind: RefusalKind
  let message: String

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case error
  }

  enum ErrorKeys: String, CodingKey {
    case kind
    case message
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    // A missing command is `null`, not an absent key: the schema requires the key.
    try container.encode(
      command,
      forKey: .command,
    )

    var error = container.nestedContainer(
      keyedBy: ErrorKeys.self,
      forKey: .error,
    )
    try error.encode(
      kind.rawValue,
      forKey: .kind,
    )
    try error.encode(
      message,
      forKey: .message,
    )
  }

  /// The document as the one JSON value stdout holds.
  func jsonText() throws(RefusalDocumentError) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let data: Data
    do {
      data = try encoder.encode(self)
    } catch {
      throw .encodingFailed
    }

    guard let text = String(
      bytes: data,
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }
}
