import Foundation
@testable import UseCasesCLI

/// Folders that are there as the test says.
struct MockFolderChecking: FolderChecking {
  let existing: Set<String>

  func isFolder(_ folder: URL) -> Bool {
    existing.contains(folder.path)
  }
}
