import Foundation
@testable import UseCasesCore

/// The local file writer, except that it cannot publish a folder: the run is made and never
/// appears. It shows what is on disk at the moment publishing fails.
struct PublishFailingFileWriter: StoreFileWriting {
  private let local = LocalStoreFileWriter()

  func ensureFolder(at folder: URL) throws(StoreWritingError) {
    try local.ensureFolder(at: folder)
  }

  func createFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.createFile(
      bytes,
      at: file,
    )
  }

  func replaceFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.replaceFile(
      bytes,
      at: file,
    )
  }

  func append(
    _ bytes: [UInt8],
    to file: URL,
  ) throws(StoreWritingError) {
    try local.append(
      bytes,
      to: file,
    )
  }

  func publishFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.publishFile(
      bytes,
      at: file,
    )
  }

  func publishExecutableFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try local.publishExecutableFile(
      bytes,
      at: file,
    )
  }

  func publishFolder(
    _ folder: URL,
    as published: URL,
  ) throws(StoreWritingError) {
    throw .unwritable(
      location: published.path,
      reason: "the test would not publish it",
    )
  }

  func flushFolder(at folder: URL) throws(StoreWritingError) {
    try local.flushFolder(at: folder)
  }

  func discard(_ item: URL) {
    local.discard(item)
  }
}
