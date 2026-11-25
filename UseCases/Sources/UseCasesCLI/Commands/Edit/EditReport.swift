import Foundation
import UseCasesCore

/// What `use-cases save` and `use-cases remove` print (chapter 16 §14): the use case and what
/// became of it, each file it changes and the warnings, for a person; one JSON document for
/// scripts. Under `--dry-run` the same, in the words of what would happen.
struct EditReport {
  private let command: String
  private let change: UseCaseChange
  private let notes: [String]
  private let isDryRun: Bool

  /// - Parameters:
  ///   - command: `save` or `remove`.
  ///   - change: What the command did, or would do.
  ///   - notes: What there is to say beside it: a cancellation that came too late. A document
  ///     has no field for it, so there it is one of the warnings.
  ///   - isDryRun: Whether nothing was written (chapter 16 §17).
  init(
    command: String,
    change: UseCaseChange,
    notes: [String],
    isDryRun: Bool,
  ) {
    self.command = command
    self.change = change
    self.notes = notes
    self.isDryRun = isDryRun
  }

  /// `saved: <use case> (<action>)` or `removed: <use case>`; a line for each file it changes,
  /// then the warnings; and the hint to look at a saved use case (chapter 16 §18) unless it is
  /// left out.
  func humanText(hint: Bool) -> String {
    var lines = [headline]

    lines += change.writes.changes.map { file in
      "\(isDryRun ? "would " : "")\(Self.word(for: file.action))  \(file.path)"
    }

    lines += (change.warnings + notes).map { warning in
      "warning: \(warning)"
    }

    if hint, command == SaveCommand.name, !isDryRun {
      lines.append("→ use-cases status \(change.identifier)")
    }

    return lines.joined(separator: "\n")
  }

  /// The document of `cli-save.schema.json` or `cli-remove.schema.json`.
  func jsonText() throws(EditReportError) -> String {
    let document = StoreJSONValue.members([
      "output_version": .integer(OutputDocument.version),
      "command": .string(command),
      "use_case": .string(change.identifier),
      "file": .string(change.file),
      "action": .string(change.action.rawValue),
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

  private var headline: String {
    if command == SaveCommand.name {
      let verb = isDryRun ? "would save" : "saved"

      return "\(verb): \(change.identifier) (\(change.action.rawValue))"
    }

    return "\(isDryRun ? "would remove" : "removed"): \(change.identifier)"
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
