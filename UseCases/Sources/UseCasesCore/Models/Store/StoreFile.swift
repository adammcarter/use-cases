import Foundation

/// A file or folder of the store: where it is on disk, and how an error names it (relative to the
/// workspace root, written with `/`).
struct StoreFile: Equatable, Sendable {
  let url: URL
  let location: String

  /// The store folder of a workspace.
  init(workspace: URL) {
    url = URL(
      fileURLWithPath: "\(workspace.path)/\(StoreLayout.storeFolder)",
      isDirectory: false,
    )
    location = StoreLayout.storeLocation
  }

  private init(
    url: URL,
    location: String,
  ) {
    self.url = url
    self.location = location
  }

  /// The place of a name below this one. Built from text, so it never gains a trailing slash.
  func appending(_ name: String) -> StoreFile {
    StoreFile(
      url: URL(
        fileURLWithPath: "\(url.path)/\(name)",
        isDirectory: false,
      ),
      location: "\(location)/\(name)",
    )
  }
}
