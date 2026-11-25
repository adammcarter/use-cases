/// Finds where a locator lands in the files of the workspace: the lines it reports and the bytes
/// it selects (chapter 08 "Manual bindings", chapter 11 §89.5). A manual binding and a link a
/// transformer names are placed the same way.
protocol LocatorPlacing: Sendable {
  /// - Parameters:
  ///   - locator: The file, and the lines in it when it is not the whole file.
  ///   - context: What discovery leaves out, and where the workspace is on disk.
  ///   - files: What earlier placements read, so that a file is read once.
  /// - Throws: ``ManualBindingProblem`` when the file is not there as spelled, is not a file,
  ///   cannot be read, or does not hold the range.
  func place(
    _ locator: ManualLocator,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(ManualBindingProblem) -> ManualPlacement
}
