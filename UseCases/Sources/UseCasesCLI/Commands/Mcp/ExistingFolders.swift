import Foundation

/// Looks at the file system.
struct ExistingFolders: FolderChecking {
  func isFolder(_ folder: URL) -> Bool {
    var isDirectory: ObjCBool = false

    return FileManager.default.fileExists(
      atPath: folder.path,
      isDirectory: &isDirectory,
    ) && isDirectory.boolValue
  }
}
