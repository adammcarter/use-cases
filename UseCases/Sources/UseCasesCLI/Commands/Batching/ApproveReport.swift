import Foundation
import UseCasesCore

/// What `use-cases approve` prints (chapter 16 §14): each use case and whether its sign-off was
/// recorded, then each file it changes, for a person; one JSON document for scripts. Under
/// `--dry-run` the same, in the words of what would happen.
struct ApproveReport: WriteReporting {
  private let change: UseCaseApprovalChange
  private let notes: [String]
  private let isDryRun: Bool

  /// - Parameters:
  ///   - change: What the sign-off did, or would do.
  ///   - notes: What there is to say beside it: a cancellation that came too late.
  ///   - isDryRun: Whether nothing was written (chapter 16 §17).
  init(
    change: UseCaseApprovalChange,
    notes: [String],
    isDryRun: Bool,
  ) {
    self.change = change
    self.notes = notes
    self.isDryRun = isDryRun
  }

  /// A line for each use case, a blank line, a line for each file and then the warnings; one
  /// line saying so when there is no use case to approve, the same with `--dry-run`.
  func humanText() -> String {
    if change.useCases.isEmpty {
      let warnings = (change.warnings + notes).map { warning in
        "warning: \(warning)"
      }

      return (["nothing needs approval"] + warnings).joined(separator: "\n")
    }

    let verbs = change.useCases.map { useCase in
      verb(for: useCase.action)
    }
    let width = verbs.map(\.count).max() ?? 0
    var lines = zip(verbs, change.useCases).map { verb, useCase in
      "\(verb.padded(toWidth: width))  \(useCase.identifier)"
    }

    if !change.writes.changes.isEmpty {
      lines.append("")
    }

    lines += change.writes.changes.map { file in
      "\(isDryRun ? "would " : "")\(Self.word(for: file.action))  \(file.path)"
    }

    lines += (change.warnings + notes).map { warning in
      "warning: \(warning)"
    }

    return lines.joined(separator: "\n")
  }

  /// The document of `cli-approve.schema.json`.
  func jsonText() throws(EditReportError) -> String {
    let document = StoreJSONValue.members([
      "output_version": .integer(OutputDocument.version),
      "command": .string(ApproveCommand.name),
      "by": .string(change.approver),
      "use_cases": .array(
        change.useCases.map { useCase in
          .members([
            "use_case": .string(useCase.identifier),
            "file": .string(useCase.file),
            "action": .string(useCase.action.rawValue),
          ])
        },
      ),
      "changes": .array(
        change.writes.changes.map { file in
          .members([
            "path": .string(file.path),
            "action": .string(file.action.rawValue),
          ])
        },
      ),
      "warnings": .strings(change.warnings + notes),
      "dry_run": .boolean(isDryRun),
    ])

    guard let text = String(
      bytes: StoreJSONWriter().pretty(document),
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }

  private func verb(for action: ApprovalAction) -> String {
    switch action {
    case .approved:
      isDryRun ? "would approve" : "approved"
    case .unchanged:
      "unchanged"
    }
  }

  private static func word(for action: FileChangeAction) -> String {
    switch action {
    case .create:
      "create"
    case .replace:
      "update"
    case .delete:
      "delete"
    }
  }
}
