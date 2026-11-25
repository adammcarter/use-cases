import Foundation
import UseCasesCore

/// What `use-cases show` prints (chapter 16 §14): the use case as YAML for a person, one JSON
/// document for scripts.
struct ShowReport {
  private let shown: ShownUseCase

  init(_ shown: ShownUseCase) {
    self.shown = shown
  }

  /// A line saying where the use case is written and whether it is READY, then the use case as
  /// the YAML `save` would write it. The line is a YAML comment, so what is printed can be
  /// saved as it is.
  func humanText() -> String {
    ([headline] + shown.yamlLines).joined(separator: "\n")
  }

  /// The document of `cli-show.schema.json`: the definition as `save` takes it, and its
  /// approval, always.
  func jsonText() throws(ShowReportError) -> String {
    let document = StoreJSONValue.members([
      "output_version": .integer(OutputDocument.version),
      "command": .string(ShowCommand.name),
      "use_case": .string(shown.identifier),
      "file": .string(shown.file),
      "state": .string(state),
      "missing": .strings(shown.missing),
      "definition": shown.definition,
      "approval": .string(shown.approval.rawValue),
    ])

    guard let text = String(
      bytes: StoreJSONWriter().pretty(document),
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }

  private var state: String {
    shown.isReady ? "READY" : "DRAFT"
  }

  private var headline: String {
    "# \(shown.file) · \(state)"
  }
}
