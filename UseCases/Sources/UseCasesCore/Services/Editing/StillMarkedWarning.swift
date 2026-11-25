/// Says which marked regions of code still name use cases that are taken out (chapter 16 §14).
protocol StillMarkedWarning: Sendable {
  /// A line for each marked region that still names one of the use cases, by file, then by
  /// place, then by use case, whichever use case it names.
  ///
  /// - Parameters:
  ///   - identifiers: The full ids of the use cases taken out.
  ///   - links: The links of the workspace as it is.
  func warnings(
    for identifiers: [String],
    in links: [ResolvedLink],
  ) -> [String]
}
