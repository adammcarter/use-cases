import Foundation

/// Where a validation's report goes inside a run (chapter 10 §8, chapter 12 §15).
struct ReportPaths: Equatable, Sendable {
  let validation: BridgeValidation

  /// `reports/<id>` or `reports/<id>/<name>`, relative to the run's folder.
  var relative: String {
    guard let name = validation.report else {
      return "\(StoreLayout.reportsFolder)/\(validation.identifier.text)"
    }

    return "\(StoreLayout.reportsFolder)/\(validation.identifier.text)/\(name)"
  }

  /// The validation's own reports folder, relative to the run's folder.
  var folder: String {
    "\(StoreLayout.reportsFolder)/\(validation.identifier.text)"
  }

  /// The absolute `{report}` of the run.
  func absolute(
    of run: RunIdentifier,
    in workspace: URL,
  ) -> String {
    "\(workspace.path)/\(StoreLayout.storeFolder)/\(StoreLayout.runsFolder)/\(run.text)/\(relative)"
  }
}
