import Foundation
import UseCasesCore

/// What `use-cases hooks` prints (chapter 18 §5): what the request did to the hooks, then each
/// hook and what it runs, then the notes and one hint; one JSON document for scripts.
struct HooksReport {
  private static let nameColumn = 9
  private static let stateColumn = 15

  private let plan: HooksPlan
  private let action: HookAction?
  private let notes: [String]
  private let isDryRun: Bool

  /// - Parameters:
  ///   - plan: What the request comes to.
  ///   - action: What was asked; `nil` only looked.
  ///   - notes: What is told besides what the plan holds: a cancellation that came too late.
  ///   - isDryRun: Whether nothing was written (chapter 16 §17).
  init(
    plan: HooksPlan,
    action: HookAction?,
    notes: [String],
    isDryRun: Bool,
  ) {
    self.plan = plan
    self.action = action
    self.notes = notes
    self.isDryRun = isDryRun
  }

  /// A line for each hook added or removed, one for each hook with what it is and runs, the
  /// notes, and the one hint line (chapter 16 §18) when it is wanted: after a plain listing with
  /// a hook not installed.
  func humanText(hint: Bool) -> String {
    var lines = plan.changed.map { hook in
      "\(verb) the \(hook.rawValue) hook"
    }

    lines += plan.hooks.map { hook in
      hook.name.rawValue.padded(toWidth: Self.nameColumn)
        + stateWords(for: hook).padded(toWidth: Self.stateColumn)
        + hook.name.runs
    }

    lines += (plan.notes + notes).map { note in
      "note: \(note)"
    }

    let missing = plan.hooks.filter { hook in
      hook.state == .absent
    }.map(\.name.rawValue)

    if hint, action == nil, !missing.isEmpty {
      lines.append("→ use-cases hooks add " + missing.joined(separator: " "))
    }

    return lines.joined(separator: "\n")
  }

  func jsonText() throws(HooksReportError) -> String {
    let document = HooksDocument(
      plan: plan,
      notes: notes,
      isDryRun: isDryRun,
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

  private var verb: String {
    switch (action, isDryRun) {
    case (.remove?, true):
      "would remove"
    case (.remove?, false):
      "removed"
    case (_, true):
      "would add"
    case (_, false):
      "added"
    }
  }

  /// What a hook is after the request; under `--dry-run`, a hook the request would change says
  /// so, because nothing was installed or removed (chapter 16 §17: people see "would").
  private func stateWords(for hook: HookStatus) -> String {
    guard isDryRun, plan.changed.contains(hook.name) else {
      return Self.words(for: hook.state)
    }

    return action == .remove ? "would remove" : "would install"
  }

  private static func words(for state: HookState) -> String {
    switch state {
    case .installed:
      "installed"
    case .absent:
      "not installed"
    case .other:
      "other"
    case .managed:
      "managed"
    }
  }
}
