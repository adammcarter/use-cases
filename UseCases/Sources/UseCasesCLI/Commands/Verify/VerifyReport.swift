import Foundation
import UseCasesCore

/// What `use-cases verify` prints (chapter 16 §11): lines for people, one JSON document for
/// scripts.
enum VerifyReport {
  /// `started run <id>`, where each report goes, anything else worth knowing, and the hint that
  /// says what to do next (chapter 16 §18).
  static func humanText(
    start started: StartedVerifyRun,
    hint: Bool,
  ) -> String {
    guard let identifier = started.runIdentifier else {
      return started.notes.joined(separator: "\n")
    }

    var lines = ["started run \(identifier)"]
    let width = started.reports.map(\.validation.count).max() ?? 0

    for report in started.reports {
      lines.append(
        "  \(report.validation.padding(toLength: width, withPad: " ", startingAt: 0))   "
          + "write the report to \(report.path)",
      )
    }

    lines += started.notes.dropFirst()

    if hint {
      lines.append("→ run your tests, then: use-cases verify --finish --run-id \(identifier)")
    }

    return lines.joined(separator: "\n")
  }

  /// `run <id> · 5 verdicts (4 pass, 1 fail) · 0 run errors`, each run error, the tests tied to
  /// no use case, and the hint to ask the gate (chapter 16 §11).
  static func humanText(
    finish run: VerifiedRun,
    hint: Bool,
  ) -> String {
    guard let identifier = run.runIdentifier else {
      return run.notes.joined(separator: "\n")
    }

    let counts = run.verdictCounts.map { verdict in
      "\(verdict.count) \(verdict.status)"
    }.joined(separator: ", ")
    let verdicts = run.verdictCount == 1 ? "1 verdict" : "\(run.verdictCount) verdicts"
    let notTied = run.notTiedTests
    let errors = run.errors.count == 1 ? "1 run error" : "\(run.errors.count) run errors"
    var lines = [
      "run \(run.shortRunIdentifier ?? identifier) · \(verdicts)"
        + (counts.isEmpty ? "" : " (\(counts))")
        + " · \(errors)"
        + (notTied.isEmpty ? "" : " · \(notTied.count) not tied to a use case"),
    ]

    lines += run.errors.map { error in
      "  ! \(error)"
    }

    if !notTied.isEmpty {
      lines.append("test not tied to a use case")
      lines += notTied.map { test in
        let place = test.file.map { file in
          guard let line = test.line else {
            return file
          }

          return "\(file):\(line)"
        } ?? "(no place)"

        return "  \(place)  \(test.status)  \(test.name)"
      }
    }

    lines += run.notes

    if hint {
      lines.append("→ use-cases status --gate")
    }

    return lines.joined(separator: "\n")
  }

  static func humanText(
    abort aborted: AbortedVerifyRun,
    notes: [String] = [],
  ) -> String {
    (["aborted run \(aborted.runIdentifier)"] + notes).joined(separator: "\n")
  }

  static func jsonText(start started: StartedVerifyRun) throws(VerifyReportError) -> String {
    try text(of: VerifyStartDocument(started: started))
  }

  static func jsonText(
    abort aborted: AbortedVerifyRun,
    notes: [String] = [],
  ) throws(VerifyReportError) -> String {
    try text(
      of: VerifyAbortDocument(
        aborted: aborted,
        notes: notes,
      ),
    )
  }

  private static func text(of document: some Encodable) throws(VerifyReportError) -> String {
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
}
