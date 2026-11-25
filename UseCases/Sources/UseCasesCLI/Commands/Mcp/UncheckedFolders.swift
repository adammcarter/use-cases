import Foundation

/// Takes every folder to be there: what a command line is run with when no folder is looked at.
struct UncheckedFolders: FolderChecking {
  func isFolder(_: URL) -> Bool {
    true
  }
}
