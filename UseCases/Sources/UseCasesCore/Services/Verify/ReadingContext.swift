import Foundation

/// What reading one validation's report works with.
struct ReadingContext {
  let validation: BridgeValidation
  let run: OpenRun
  let resolved: ResolvedWorkspace
  let ran: RanCommand?
  let runner: any TransformerRunning

  var paths: ReportPaths {
    ReportPaths(validation: validation)
  }

  /// The validation's reports folder in the run.
  var folder: StoreFile {
    StoreFile(workspace: run.workspace)
      .appending(StoreLayout.runsFolder)
      .appending(run.identifier.text)
      .appending(StoreLayout.reportsFolder)
      .appending(validation.identifier.text)
  }

  /// The report itself: the folder, or the file the validation names inside it.
  var report: StoreFile {
    guard let name = validation.report else {
      return folder
    }

    return folder.appending(name)
  }

  /// The keys a result may name: the validation links of the workspace.
  var validationKeys: Set<String> {
    Set(
      resolved.links.links.filter { $0.role == .validation }.map(\.key),
    )
  }

  /// The source as the manifest keeps it.
  func source(
    error: String? = nil,
    diagnostics: [String] = [],
  ) -> RunSource {
    RunSource.recorded(
      for: validation,
      ran: ran,
      error: error,
      diagnostics: diagnostics,
    )
  }

  /// The outcome of a source that has no results: it went wrong, or it was cancelled.
  func outcome(
    error: String? = nil,
    readReports: [FileDigest] = [],
    isCancelled: Bool = false,
  ) -> SourceOutcome {
    SourceOutcome(
      source: source(error: error),
      results: [],
      unlinked: [],
      readReports: readReports,
      isCancelled: isCancelled,
    )
  }
}
