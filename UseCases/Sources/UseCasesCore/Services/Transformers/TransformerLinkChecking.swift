/// Checks a link a links transformer returned, and places it (chapter 10 §11): the core trusts a
/// links transformer for nothing.
protocol TransformerLinkChecking: Sendable {
  /// The link as the core holds links: a known use case, a known route for a validation link and
  /// none for an implementation link, an existing file inside the workspace and outside every
  /// excluded folder, and a range inside that file.
  ///
  /// - Parameters:
  ///   - link: What the transformer returned.
  ///   - name: The transformer, for the message.
  ///   - targets: The use cases the link may name.
  ///   - context: What discovery leaves out, and where the workspace is on disk.
  ///   - files: What earlier links read, so that a file is read once.
  /// - Throws: ``TransformerError/badLink(name:link:problem:)`` for any other link.
  func resolve(
    _ link: TransformerLink,
    from name: String,
    among targets: LinkTargets,
    context: DiscoveryContext,
    files: inout BoundFiles,
  ) throws(TransformerError) -> ResolvedLink
}
