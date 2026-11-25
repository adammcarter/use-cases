/// Runs the links job of every link transformer of the bridge settings (chapter 10 §11,
/// chapter 09 §20.4).
public protocol TransformerLinkProviding: Sendable {
  /// The links the transformers return, in the order the bridge settings list them.
  ///
  /// Starts a process for each `links:` entry, in the workspace root, and waits for it. A workspace
  /// with none configured starts nothing.
  ///
  /// - Parameter workspace: A workspace that loaded.
  /// - Returns: The checked links, and the transformers' own words about them.
  /// - Throws: ``TransformerLinkingError`` when a transformer gives no usable answer, or a link it
  ///   returns cannot be placed: the link set is then unknown, so the workspace cannot load.
  func links(for workspace: LoadedWorkspace) async throws(TransformerLinkingError)
    -> TransformedLinks
}
