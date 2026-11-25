/// The files of a workspace, listed the same way every time.
protocol SourceListing: Sendable {
  /// Workspace-relative paths of the files under `folder` whose path from `folder` matches
  /// `pattern`: a folder's files in name order, then its subfolders in name order. `folder` is
  /// workspace-relative; "" is the code root.
  func files(
    matching pattern: String,
    under folder: String,
  ) -> [String]

  /// Workspace-relative paths of the files directly inside `folder`, in name order.
  func files(directlyIn folder: String) -> [String]
}
