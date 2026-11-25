import Foundation
import UseCasesCore

/// What `use-cases validate` prints for a valid workspace (chapter 16 §8): a line and its
/// warnings for people, one JSON document for scripts.
struct ValidateReport {
  private let summary: WorkspaceSummary
  private let linkCount: Int
  private let warnings: [String]

  /// - Parameters:
  ///   - summary: The use cases and the files read.
  ///   - linkCount: The number of link keys: one per marker region, manual binding or transformer
  ///     link (chapter 16 §8).
  ///   - warnings: Everything worth saying that does not make the workspace INVALID.
  init(
    summary: WorkspaceSummary,
    linkCount: Int,
    warnings: [String],
  ) {
    self.summary = summary
    self.linkCount = linkCount
    self.warnings = warnings
  }

  /// `✓ valid · 12 use cases (10 ready, 2 draft) · 31 links · 14 files`, then each warning on a
  /// line, then the one hint line (chapter 16 §18) when it is wanted.
  func humanText(hint: Bool) -> String {
    let counts = [
      "✓ valid",
      "\(Self.counted(summary.useCases, "use case")) (\(summary.ready) ready, "
        + "\(summary.draft) draft)",
      Self.counted(linkCount, "link"),
      Self.counted(summary.files.count, "file"),
    ]

    var lines = [counts.joined(separator: " · ")]
    lines += warnings.map { warning in
      "warning: \(warning)"
    }

    if hint {
      lines.append("→ use-cases status")
    }

    return lines.joined(separator: "\n")
  }

  func jsonText() throws(ValidateReportError) -> String {
    let document = ValidateDocument(
      summary: summary,
      linkCount: linkCount,
      warnings: warnings,
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

    let data: Data
    do {
      data = try encoder.encode(document)
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

  private static func counted(
    _ count: Int,
    _ noun: String,
  ) -> String {
    "\(count) \(noun)\(count == 1 ? "" : "s")"
  }
}
