import Foundation
import MCP

/// Writes frames one at a time, in the order they were asked for, each to its end before the next
/// begins. The standard output transport of the SDK waits inside a write when the host is slow to
/// read, and a second write started meanwhile goes out in the middle of the first; a host cannot
/// read a frame cut in two. Every write here is a task of its own, so the call that asked for it
/// being cancelled cannot cut a frame short either.
actor FrameWriter: FrameWriting {
  private let transport: any Transport
  private var isWriting = false
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private let onQueued: (@Sendable () -> Void)?

  /// - Parameters:
  ///   - transport: Where the frames are written.
  ///   - onQueued: Called each time a frame has to wait for the one before it, once it is in line.
  init(
    transport: any Transport,
    onQueued: (@Sendable () -> Void)? = nil,
  ) {
    self.transport = transport
    self.onQueued = onQueued
  }

  func write(_ frame: Data) async throws {
    await takeTurn()
    let transport = transport
    let writing = Task {
      try await transport.send(frame)
    }

    do {
      try await writing.value
    } catch {
      endTurn()

      throw error
    }

    endTurn()
  }

  private func takeTurn() async {
    guard isWriting else {
      isWriting = true

      return
    }

    await withCheckedContinuation { continuation in
      waiting.append(continuation)
      onQueued?()
    }
  }

  private func endTurn() {
    guard !waiting.isEmpty else {
      isWriting = false

      return
    }

    // The turn passes to the first in line; the writer is never free in between.
    waiting.removeFirst().resume()
  }
}
