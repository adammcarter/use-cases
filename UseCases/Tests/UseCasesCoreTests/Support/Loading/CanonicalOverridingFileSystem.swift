import Foundation
@testable import UseCasesCore

/// The local file system, except that it says where chosen paths lead once their symlinks are
/// resolved. It lets a test show what the core does with a location it could not otherwise be
/// given, such as a path that resolves into the results store.
struct CanonicalOverridingFileSystem: FileSystemReading {
  private let local = LocalFileSystem()
  private let leads: [String: URL]

  /// - Parameter leads: For each path, by its text, the place the system says it resolves to.
  init(leads: [String: URL]) {
    self.leads = leads
  }

  func canonicalLocation(of url: URL) -> URL {
    leads[url.path] ?? local.canonicalLocation(of: url)
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
