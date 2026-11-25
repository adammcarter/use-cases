import Foundation
import UseCasesCore

/// What `use-cases apply` prints (chapter 16 §14): each use case and what became of it in the
/// order the batch runs, then each file it changes and the warnings, for a person; one JSON
/// document for scripts. Under `--dry-run` the same, in the words of what would happen.
struct ApplyReport: WriteReporting {
  private let change: UseCaseBatchChange
  private let notes: [String]
  private let isDryRun: Bool

  /// - Parameters:
  ///   - change: What the batch did, or would do.
  ///   - notes: What there is to say beside it: a cancellation that came too late. A document
  ///     has no field for it, so there it is one of the warnings.
  ///   - isDryRun: Whether nothing was written (chapter 16 §17).
  init(
    change: UseCaseBatchChange,
    notes: [String],
    isDryRun: Bool,
  ) {
    self.change = change
    self.notes = notes
    self.isDryRun = isDryRun
  }

  /// A line for each use case, a blank line, a line for each file and then the warnings.
  func humanText() -> String {
    var lines = change.useCases.map { useCase in
      "\(prefix)\(Self.word(for: useCase.action).padded(toWidth: 6))  \(useCase.identifier)"
    }

    if !change.writes.changes.isEmpty {
      lines.append("")
    }

    lines += change.writes.changes.map { file in
      "\(prefix)\(Self.word(for: file.action))  \(file.path)"
    }

    lines += (change.warnings + notes).map { warning in
      "warning: \(warning)"
    }

    return lines.joined(separator: "\n")
  }

  /// The document of `cli-apply.schema.json`.
  func jsonText() throws(EditReportError) -> String {
    let document = StoreJSONValue.members([
      "output_version": .integer(OutputDocument.version),
      "command": .string(ApplyCommand.name),
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

  private var prefix: String {
    isDryRun ? "would " : ""
  }

  private static func word(for action: UseCaseChangeAction) -> String {
    switch action {
    case .removed:
      "delete"
    case .created, .added:
      "add"
    case .replaced:
      "update"
    case .unchanged:
      "keep"
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
