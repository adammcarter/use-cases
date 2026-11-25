import Foundation
@testable import UseCasesCore

/// The local file system, telling a log how its files were read: whole, or in chunks of what
/// size. A test that must show a file is never held whole shows that nothing read it whole.
struct ChunkAccountingFileSystem: FileSystemReading {
  private let local = LocalFileSystem()
  let log: ChunkLog

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
    log.readWhole()

    return try local.readText(at: file)
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    log.readWhole()

    return try local.readBytes(at: file)
  }

  func chunks(of file: URL) throws(FileSystemError) -> any FileChunkReading {
    try AccountingChunkReader(
      local.chunks(of: file),
      log: log,
    )
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
