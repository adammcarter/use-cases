import Foundation
@testable import UseCasesCore

/// The local file system, writing one line to a log file for every read of a file's bytes or a
/// symlink's text. The count lives on disk, so no state is shared between threads.
struct CountingFileSystem: FileSystemReading {
  private let local = LocalFileSystem()
  private let log: URL

  /// Starts a log at `log`, which must be outside the workspace being read.
  init(log: URL) throws {
    self.log = log
    try Data().write(to: log)
  }

  /// How many times each file was read, by location.
  func reads() throws -> [String: Int] {
    let text = try String(contentsOf: log, encoding: .utf8)
    var counts: [String: Int] = [:]

    for line in text.split(separator: "\n") {
      counts[String(line), default: 0] += 1
    }

    return counts
  }

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
    record(file)

    return try local.readText(at: file)
  }

  func readBytes(at file: URL) throws(FileSystemError) -> [UInt8] {
    record(file)

    return try local.readBytes(at: file)
  }

  func targetText(ofSymlinkAt link: URL) throws(FileSystemError) -> String {
    record(link)

    return try local.targetText(ofSymlinkAt: link)
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

  private func record(_ file: URL) {
    guard
      let handle = try? FileHandle(forWritingTo: log),
      let line = (file.path + "\n").data(using: .utf8)
    else {
      return
    }

    defer {
      try? handle.close()
    }

    _ = try? handle.seekToEnd()
    try? handle.write(contentsOf: line)
  }
}
