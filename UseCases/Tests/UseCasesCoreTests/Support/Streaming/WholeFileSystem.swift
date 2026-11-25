import Foundation
@testable import UseCasesCore

/// The local file system as a file system that cannot stream is: every file is read whole and
/// handed out in chunks. What is worked out of it is what is worked out of the same file by
/// streaming, which is what a test of streaming compares.
struct WholeFileSystem: FileSystemReading {
  private let local = LocalFileSystem()

  func canonicalLocation(of url: URL) -> URL {
    local.canonicalLocation(of: url)
  }

  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    try local.kindOfItem(at: url)
  }

  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    try local.entries(in: folder)
  }

  func readText(at file: URL) throws(FileSystemError) -> String {
    try local.readText(at: file)
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    try local.readBytes(at: file)
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    try local.targetText(ofSymlinkAt: link)
  }

  func holdsFile(
    named name: String,
    below folder: FileEntry,
    in parent: URL,
  ) -> Bool {
    local.holdsFile(
      named: name,
      below: folder,
      in: parent,
    )
  }
}
