import Foundation
@testable import UseCasesTransformers

/// A reader over files held in memory.
struct MockReportReader: ReportReading {
  let texts: [String: String]

  func exists(at path: String) -> Bool {
    texts[path] != nil
  }

  func isFolder(at _: String) -> Bool {
    false
  }

  func files(under _: String) -> [String] {
    texts.keys.sorted()
  }

  func data(at path: String) throws(TransformerFailure) -> Data {
    try Data(text(at: path).utf8)
  }

  func text(at path: String) throws(TransformerFailure) -> String {
    guard let text = texts[path] else {
      throw .reportUnreadable(
        path: path,
        reason: "not in the mock",
      )
    }

    return text
  }

  func lossyText(at path: String) throws(TransformerFailure) -> String {
    try text(at: path)
  }

  func sourceText(at path: String) -> String? {
    texts[path]
  }
}
