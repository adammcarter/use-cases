import Foundation
@testable import UseCasesCore

/// The local file writer, noting the folders it was asked to make, so that a test can look in
/// them afterwards.
final class FolderNotingFileWriter: StoreFileWriting {
  private let local = LocalStoreFileWriter()
  private let log: URL

  init() {
    log = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-folders-\(UUID().uuidString)")
    _ = FileManager.default.createFile(atPath: log.path, contents: nil)
  }

  deinit {
    try? FileManager.default.removeItem(at: log)
  }

  /// The folders made, in order.
  var folders: [URL] {
    let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""

    return text.split(separator: "\n").map { path in
      URL(fileURLWithPath: String(path))
    }
  }

  func ensureFolder(at folder: URL) throws(StoreWritingError) {
    note(folder)

    try local.ensureFolder(at: folder)
  }

  func createFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.createFile(bytes, at: file)
  }

  func replaceFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.replaceFile(bytes, at: file)
  }

  func append(
    _ bytes: [UInt8],
    to file: URL,
  ) throws(StoreWritingError) {
    try local.append(bytes, to: file)
  }

  func stageFile(
    copying source: any FileChunkReading,
    in folder: URL,
  ) throws(StoreWritingError) -> URL {
    try local.stageFile(copying: source, in: folder)
  }

  func publishStagedFile(
    _ staged: URL,
    at file: URL,
  ) throws(StoreWritingError) {
    try local.publishStagedFile(staged, at: file)
  }

  func publishFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.publishFile(bytes, at: file)
  }

  func publishExecutableFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.publishExecutableFile(bytes, at: file)
  }

  func publishFolder(
    _ folder: URL,
    as published: URL,
  ) throws(StoreWritingError) {
    try local.publishFolder(folder, as: published)
  }

  func flushFolder(at folder: URL) throws(StoreWritingError) {
    try local.flushFolder(at: folder)
  }

  func discard(_ item: URL) {
    local.discard(item)
  }

  private func note(_ folder: URL) {
    guard
      let handle = try? FileHandle(forWritingTo: log),
      let line = (folder.path + "\n").data(using: .utf8)
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
