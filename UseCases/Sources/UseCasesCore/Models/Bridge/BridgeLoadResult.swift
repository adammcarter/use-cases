/// What loading the bridge settings found: the settings when the file is there and is valid, and
/// every problem otherwise.
struct BridgeLoadResult: Equatable, Sendable {
  /// `nil` when there is no bridge file, and when it has a problem.
  let settings: BridgeSettings?
  let diagnostics: [Diagnostic]
}
