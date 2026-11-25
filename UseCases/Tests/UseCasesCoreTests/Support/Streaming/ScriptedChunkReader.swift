import Foundation
@testable import UseCasesCore

/// A chunk reader that gives the chunks a test wrote, says the length the test wants it to say,
/// and fails when the test wants it to, after the chunks that come before the failure.
final class ScriptedChunkReader: FileChunkReading {
  let length: Int

  private var chunks: [[UInt8]]
  private let failure: FileSystemError?

  /// - Parameters:
  ///   - chunks: What is given, one after the other, before the end or the failure.
  ///   - length: What `length` says; the bytes of the chunks when `nil`.
  ///   - failure: What is thrown, in place of the end, when the chunks have been given.
  init(
    chunks: [[UInt8]],
    length: Int? = nil,
    failure: FileSystemError? = nil,
  ) {
    self.chunks = chunks
    self.length = length ?? chunks.reduce(0) { $0 + $1.count }
    self.failure = failure
  }

  func nextChunk() throws(FileSystemError) -> [UInt8] {
    if !chunks.isEmpty {
      return chunks.removeFirst()
    }
    if let failure {
      throw failure
    }

    return []
  }
}
