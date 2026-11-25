import Foundation

/// Writes the request of a results job (chapter 10 §13).
protocol ResultsRequestBuilding: Sendable {
  /// The request document for one validation's report.
  ///
  /// - Parameters:
  ///   - validation: The validation whose report is read.
  ///   - workspace: The workspace as it is at the finish point.
  ///   - links: Its links: every key a result may name is a validation link of these.
  ///   - reportPath: The absolute `{report}` of the validation in the run.
  ///   - exitCode: The run command's exit code; `nil` when the person's own tests wrote the
  ///     report and the core does not know it.
  func request(
    for validation: BridgeValidation,
    in workspace: LoadedWorkspace,
    links: LinkResolution,
    reportPath: String,
    exitCode: Int32?,
  ) -> StoreJSONValue
}
