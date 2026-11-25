import Foundation
@testable import UseCasesCore

/// The local file system with one more name in one folder, whose name is not valid UTF-8. It lets
/// every file system without such names (APFS refuses them) show how a listing that has one is
/// handled.
struct UndecodableNameFileSystem: FileSystemReading {
  /// The name, escaped as the listing escapes it.
  static let name = "bad\\xFF.js"

  private let local = LocalFileSystem()
  private let folder: URL
  private let kind: FileEntryKind
  private let holdsConfiguration: Bool

  /// A file system that lists the undecodable name in `folder`, as a file or a folder. A folder
  /// holds a `use-cases.yml` when `holdsConfiguration` says so.
  init(
    in folder: URL,
    kind: FileEntryKind = .file,
    holdsConfiguration: Bool = false,
  ) {
    self.folder = folder
    self.kind = kind
    self.holdsConfiguration = holdsConfiguration
  }

  func canonicalLocation(of url: URL) -> URL {
    local.canonicalLocation(of: url)
  }

  func kindOfItem(at url: URL) throws(FileSystemError) -> FileEntryKind? {
    try local.kindOfItem(at: url)
  }

  func entries(in listed: URL) throws(FileSystemError) -> [FileEntry] {
    let entries = try local.entries(in: listed)

    guard listed.path == folder.path else {
      return entries
    }

    let injected = FileEntry(
      name: Self.name,
      kind: kind,
      isNameUTF8: false,
      nameBytes: [0x62, 0x61, 0x64, 0xFF],
    )

    return entries + [injected]
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
    below entry: FileEntry,
    in parent: URL,
  ) -> Bool {
    guard !entry.isNameUTF8 else {
      return local.holdsFile(named: name, below: entry, in: parent)
    }

    return holdsConfiguration
  }
}
