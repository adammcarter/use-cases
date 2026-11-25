import Foundation

/// Lists, moves and deletes the folders of the store, for `prune`.
protocol StoreFolderRemoving: Sendable {
  /// The names of the folders directly in a folder; a symlink is no folder. None when the folder
  /// is not there.
  func folderNames(in folder: URL) -> [String]

  /// Whether anything is at this place, without following a symlink.
  func exists(_ item: URL) -> Bool

  /// Renames a folder within its parent, in one step; fails when the new name is taken.
  func move(
    _ folder: URL,
    to destination: URL,
  ) throws(StoreFolderError)

  /// Deletes a file, or a folder and everything in it.
  func delete(_ item: URL) throws(StoreFolderError)
}
