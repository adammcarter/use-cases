import Foundation

/// What was read of the files a test watches: how many were read whole, how many were opened to
/// be read a chunk at a time, and how big each chunk was. Each event is a line in a file of its
/// own, so that no state is shared between threads, and the file goes with the log.
final class ChunkLog: Sendable {
  private let file: URL

  init() {
    file = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-chunk-log-\(UUID().uuidString)")
    _ = FileManager.default.createFile(atPath: file.path, contents: nil)
  }

  deinit {
    try? FileManager.default.removeItem(at: file)
  }

  /// How many files were read whole.
  var wholeReadCount: Int {
    events.count { $0 == "whole" }
  }

  /// How many files were opened to be read a chunk at a time.
  var openedCount: Int {
    events.count { $0 == "open" }
  }

  /// The most bytes any chunk held.
  var largestChunk: Int {
    chunkSizes.max() ?? 0
  }

  /// The bytes of all the chunks.
  var streamedBytes: Int {
    chunkSizes.reduce(0, +)
  }

  func readWhole() {
    record("whole")
  }

  func open() {
    record("open")
  }

  func read(chunk size: Int) {
    record("chunk \(size)")
  }

  private var events: [String] {
    let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""

    return text.split(separator: "\n").map(String.init)
  }

  private var chunkSizes: [Int] {
    events.compactMap { event in
      event.hasPrefix("chunk ") ? Int(event.dropFirst("chunk ".count)) : nil
    }
  }

  private func record(_ event: String) {
    guard
      let handle = try? FileHandle(forWritingTo: file),
      let line = (event + "\n").data(using: .utf8)
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
