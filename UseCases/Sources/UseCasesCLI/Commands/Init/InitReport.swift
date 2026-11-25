import Foundation
import UseCasesCore

/// What `use-cases init` prints (chapter 17 §2, §8): the files it made and kept, what it did to
/// `.gitignore`, and one next step for people; one JSON document for scripts.
struct InitReport {
  /// What a file is for, said beside it. A file with nothing to say has no words.
  private static let comments = [
    "use-cases/example.yml": "a DRAFT example: fill it in, or delete it",
    "use-cases-bridge.yml": "a commented template: add your own test command",
  ]

  private static let commentColumn = 27

  private let plan: InitPlan
  private let hooks: [HookName]
  private let notes: [String]
  private let isDryRun: Bool

  /// - Parameters:
  ///   - plan: What `init` planned.
  ///   - hooks: The hooks this request adds, or would add.
  ///   - notes: What is told besides what the plan holds: a hook that was left alone, and a
  ///     cancellation that came too late.
  ///   - isDryRun: Whether nothing was written (chapter 16 §17).
  init(
    plan: InitPlan,
    hooks: [HookName],
    notes: [String],
    isDryRun: Bool,
  ) {
    self.plan = plan
    self.hooks = hooks
    self.notes = notes
    self.isDryRun = isDryRun
  }

  /// One line for each file made or kept, one for `.gitignore`, the notes, and the one hint line
  /// (chapter 16 §18) when it is wanted. A preview says "would" and has no next step to take.
  func humanText(hint: Bool) -> String {
    var lines = plan.created.map { path in
      line(
        isDryRun ? "would create" : "created",
        path,
      )
    }

    lines += plan.kept.map { path in
      line(
        "kept",
        path,
      )
    }

    switch plan.gitignore {
    case .added:
      lines.append(
        line(
          isDryRun ? "would add" : "added",
          ".use-cases/ to .gitignore",
          comment: false,
        ),
      )
    case .present:
      lines.append(
        line(
          "present",
          ".use-cases/ is already in .gitignore",
          comment: false,
        ),
      )
    case .skipped:
      break
    }

    lines += hooks.map { hook in
      line(
        isDryRun ? "would add" : "added",
        "the \(hook.rawValue) hook (\(hook.runs))",
        comment: false,
      )
    }

    lines += (plan.notes + notes).map { note in
      "note: \(note)"
    }

    if hint, !isDryRun {
      lines.append("→ use-cases status")
    }

    return lines.joined(separator: "\n")
  }

  func jsonText() throws(InitReportError) -> String {
    let document = InitDocument(
      workspace: plan.root.path,
      created: plan.created,
      kept: plan.kept,
      hooks: hooks.map(\.rawValue),
      gitignore: plan.gitignore,
      notes: plan.notes + notes,
      dryRun: isDryRun,
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

  private func line(
    _ action: String,
    _ subject: String,
    comment: Bool = true,
  ) -> String {
    let label = action.padded(toWidth: isDryRun ? 14 : 9)

    guard comment, let words = Self.comments[subject] else {
      return label + subject
    }

    return label + subject.padded(toWidth: Self.commentColumn) + words
  }
}
