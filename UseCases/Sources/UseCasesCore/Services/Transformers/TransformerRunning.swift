import Foundation

/// Runs one job of one transformer and brings back its checked answer (chapter 10 §10, §14).
protocol TransformerRunning: Sendable {
  /// Writes the request to a private folder, starts the transformer in the workspace root, waits
  /// at most the transformer's time, reads the response, and removes the folder.
  ///
  /// - Parameters:
  ///   - reference: The transformer, as the bridge settings name it.
  ///   - job: The job it does.
  ///   - request: The request document.
  ///   - root: The workspace root: where the transformer starts.
  /// - Returns: The response, once it is known to be a JSON object that says `"contract": 1`.
  ///   Everything else in it is still unchecked.
  /// - Throws: ``TransformerError`` when there is no answer to read.
  func run(
    _ reference: TransformerReference,
    job: TransformerJob,
    request: StoreJSONValue,
    in root: URL,
  ) async throws(TransformerError) -> AuthoredObject
}
