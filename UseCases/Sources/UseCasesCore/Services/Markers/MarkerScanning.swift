/// Reads the marker regions out of one file's bytes (chapter 08 "Markers").
///
/// It knows nothing of the file system or of which use cases exist: a region names a use case, a
/// route and a binding, and whoever knows the use cases decides whether they are real.
protocol MarkerScanning: Sendable {
  /// The regions found in `bytes` and every problem with them, each problem naming `file`.
  ///
  /// The bytes are searched for the sentinel before anything is decoded. A file without it has
  /// nothing to say, whatever it holds.
  func scan(
    _ bytes: [UInt8],
    in file: WorkspacePath,
  ) -> MarkerScan
}
