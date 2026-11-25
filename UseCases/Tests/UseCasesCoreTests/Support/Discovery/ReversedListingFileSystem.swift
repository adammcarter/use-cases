import Foundation
@testable import UseCasesCore

/// The local file system, listing every folder in the opposite order, to prove that results do
/// not depend on the order a file system happens to list names in.
struct ReversedListingFileSystem: FileSystemReading {
  private let local = LocalFileSystem()

  func canonicalLocation(of url: URL) -> URL {
    local.canonicalLocation(of: url)
  }

  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    try local.kindOfItem(at: url)
  }

  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    try Array(local.entries(in: folder).reversed())
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
