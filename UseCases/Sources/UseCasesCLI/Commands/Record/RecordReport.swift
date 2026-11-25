import Foundation
import UseCasesCore

/// What `use-cases record` prints (chapter 16 §12): a line for people, one JSON document for
/// scripts.
struct RecordReport {
  private let run: RecordedRun
  private let notes: [String]

  /// - Parameter notes: What there is to say beside the run, as the manifest's `notes`.
  init(
    run: RecordedRun,
    notes: [String] = [],
  ) {
    self.run = run
    self.notes = notes
  }

  /// `recorded: <use case> / <route> → <status>`, then the hint to look at the use case (chapter
  /// 16 §18) unless it is left out.
  func humanText(hint: Bool) -> String {
    let lines = ["recorded: \(run.useCase) / \(run.route) → \(run.status)"] + notes

    guard hint else {
      return lines.joined(separator: "\n")
    }

    return (lines + ["→ use-cases status \(run.useCase)"]).joined(separator: "\n")
  }

  func jsonText() throws(RecordReportError) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let data: Data
    do {
      data = try encoder.encode(RecordDocument(
        run: run,
        notes: notes,
      ))
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
