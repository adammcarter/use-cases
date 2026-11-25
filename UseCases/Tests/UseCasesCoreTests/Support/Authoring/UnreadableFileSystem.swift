import Foundation
@testable import UseCasesCore

/// A file system in which everything is a file that cannot be read.
struct UnreadableFileSystem: FileSystemReading {
  func canonicalLocation(of url: URL) -> URL {
    url
  }

  func kindOfItem(at _: URL) throws(FileSystemError) -> FileEntryKind? {
    .file
  }

  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    throw .unreadable(folder, reason: "permission denied")
  }

  func readText(at file: URL) throws(FileSystemError) -> String {
    throw .unreadable(file, reason: "permission denied")
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    throw .unreadable(file, reason: "permission denied")
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    throw .unreadable(link, reason: "permission denied")
  }

  func holdsFile(
    named _: String,
    below _: FileEntry,
    in _: URL,
  ) -> Bool {
    false
  }
}
