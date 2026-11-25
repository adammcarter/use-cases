import Foundation
import UseCasesCore

/// What `use-cases status` prints (chapter 16 §9, §10): a list, one use case in detail, a single
/// line for a checkout where nothing has run, or the gate's answer for people; one JSON document
/// for scripts.
struct StatusReport {
  /// The use cases the request chose, in the order of the list.
  let shown: [UseCaseStatus]
  let workspace: WorkspaceStatus

  /// The group the request chose, when it chose one.
  let group: String?

  private let offersRun: Bool

  /// - Parameters:
  ///   - workspace: What status knows about the workspace.
  ///   - shown: The use cases the target, `--group` and `--state` chose, in the order of the list.
  ///   - group: The group `--group` named, when it was given.
  ///   - offersRun: Whether some validation has a run command, which makes `verify --run` the
  ///     step to point at and not `verify --start` (chapter 16 §9).
  init(
    workspace: WorkspaceStatus,
    shown: [UseCaseStatus],
    group: String? = nil,
    offersRun: Bool,
  ) {
    self.workspace = workspace
    self.shown = shown
    self.group = group
    self.offersRun = offersRun
  }

  /// The one JSON document, with the gate's answer when the gate was asked.
  func jsonText(gate: Gate?) throws(StatusReportError) -> String {
    let document = StatusDocument(
      useCases: shown.map(StatusUseCaseEntry.init),
      summary: StatusSummary(shown),
      warnings: workspace.warnings.map { warning in
        warning.text(shortening: nil)
      },
      group: group,
      gate: gate.map(StatusGateAnswer.init),
      store: workspace.store.map(StatusStoreEntry.init),
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

  /// The step that gets verdicts, as a hint names it.
  var verifyStep: String {
    offersRun ? "verify --run" : "verify --start"
  }

  /// The warnings under a list: the empty marked regions of the use cases shown, and what is
  /// worth saying about the workspace as a whole.
  func warningLines() -> [String] {
    let owned = shown.flatMap { useCase in
      useCase.warnings.filter(\.isListed).map { warning in
        "warning: \(useCase.identifier): \(warning.text)"
      }
    }

    return owned + workspace.warnings.map { warning in
      "warning: \(warning.text(shortening: workspace.runIdentifiers))"
    }
  }

  func hintLine(_ command: String) -> String {
    "→ use-cases \(command)"
  }
}
