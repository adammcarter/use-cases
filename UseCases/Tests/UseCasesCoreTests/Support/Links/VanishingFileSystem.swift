import Foundation
@testable import UseCasesCore

/// The real file system, except that one file is deleted the moment something asks to read it:
/// another program took it away between the listing and the read.
struct VanishingFileSystem: FileSystemReading {
  let vanishing: URL
  private let base = LocalFileSystem()

  func canonicalLocation(of url: URL) -> URL {
    base.canonicalLocation(of: url)
  }

  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    try base.kindOfItem(at: url)
  }

  func entries(in folder: URL) throws(FileSystemError) -> [FileEntry] {
    try base.entries(in: folder)
  }

  func readText(at file: URL) throws(FileSystemError) -> String {
    vanishIfAsked(file)
    return try base.readText(at: file)
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    vanishIfAsked(file)
    return try base.readBytes(at: file)
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    vanishIfAsked(link)
    return try base.targetText(ofSymlinkAt: link)
  }

  func holdsFile(
    named name: String,
    below folder: FileEntry,
    in parent: URL,
  ) -> Bool {
    base.holdsFile(
      named: name,
      below: folder,
      in: parent,
    )
  }

  private func vanishIfAsked(_ file: URL) {
    if file.standardizedFileURL.path == vanishing.standardizedFileURL.path {
      try? FileManager.default.removeItem(at: file)
    }
  }
}
