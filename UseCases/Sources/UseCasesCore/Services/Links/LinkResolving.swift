/// Resolves the links of a loaded workspace (chapter 09 §20): the markers found in the code, the
/// manual bindings written in use cases, and the links the link transformers returned.
public protocol LinkResolving: Sendable {
  /// The links of `workspace`, and every problem and warning about them.
  ///
  /// Reads the workspace's code: it walks every file that is not excluded, never following a
  /// symlink. The result also carries the warnings the load itself found, so the problems and
  /// warnings of a workspace come together in one report order.
  ///
  /// - Parameters:
  ///   - workspace: A workspace that loaded.
  ///   - transformed: What the link transformers returned, already checked. They join the links
  ///     found here, and a binding two sources name is INVALID.
  /// - Returns: The links, or, when the workspace is INVALID, the problems and no links.
  func resolveLinks(
    in workspace: LoadedWorkspace,
    including transformed: TransformedLinks,
  ) -> LinkResolution
}

public extension LinkResolving {
  /// The links of a workspace that has no link transformers.
  func resolveLinks(in workspace: LoadedWorkspace) -> LinkResolution {
    resolveLinks(
      in: workspace,
      including: .none,
    )
  }
}
