import Foundation
@testable import UseCasesCore

/// The local file writer, except that it stops for a moment just after a folder is published,
/// when the test can look at the store as another process would: the run is a run, and its owner
/// has not got it back yet.
struct PausingFileWriter: StoreFileWriting {
  private let local = LocalStoreFileWriter()
  private let afterPublishing: @Sendable (URL) -> Void

  /// - Parameter afterPublishing: Called with the published folder, before anything else happens.
  init(afterPublishing: @escaping @Sendable (URL) -> Void) {
    self.afterPublishing = afterPublishing
  }

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
    try local.publishFolder(
      folder,
      as: published,
    )
    afterPublishing(published)
  }

  func flushFolder(at folder: URL) throws(StoreWritingError) {
    try local.flushFolder(at: folder)
  }

  func discard(_ item: URL) {
    local.discard(item)
  }
}
