import Foundation

/// Reading what a test tool wrote, and the source it tested. A transformer only ever reads.
protocol ReportReading: Sendable {
  func exists(at path: String) -> Bool

  func isFolder(at path: String) -> Bool

  /// The paths of every file under the folder at `path`, at any depth, in name order.
  func files(under path: String) -> [String]

  /// The bytes of the file at `path`.
  func data(at path: String) throws(TransformerFailure) -> Data

  /// The text of the file at `path`, which must be UTF-8.
  func text(at path: String) throws(TransformerFailure) -> String

  /// The text of a tool's console output at `path`. A byte that is not UTF-8 reads as U+FFFD
  /// where it stands, and nothing else about the text changes.
  func lossyText(at path: String) throws(TransformerFailure) -> String

  /// The text of a source file, or nil when it cannot be read or is not UTF-8.
  func sourceText(at path: String) -> String?
}
