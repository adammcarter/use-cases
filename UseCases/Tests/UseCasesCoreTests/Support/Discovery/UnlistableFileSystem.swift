import Foundation
@testable import UseCasesCore

/// A file system that has nothing to say about any folder: every listing and read fails.
struct UnlistableFileSystem: FileSystemReading {
  func canonicalLocation(of url: URL) -> URL {
    url
  }

  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    nil
  }

  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    throw .notFound(folder)
  }

  func readText(at file: URL) throws(FileSystemError) -> String {
    throw .notFound(file)
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    throw .notFound(file)
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    throw .notFound(link)
  }

  func holdsFile(
    named name: String,
    below folder: FileEntry,
    in parent: URL,
  ) -> Bool {
    false
  }
}
