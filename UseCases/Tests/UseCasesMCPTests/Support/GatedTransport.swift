import Foundation
import Logging
import MCP

/// A transport whose writes wait to be let go, one by one, and that remembers how they went, so
/// a test can hold a write half-done and see what else is written meanwhile. A frame is the name
/// of the write.
actor GatedTransport: Transport {
  enum Event: Equatable {
    case began(String)
    case ended(String)
  }

  /// Something a test can wait for: a write that began or ended here, or a frame that the writer
  /// above this transport held back to wait its turn.
  enum Happening: Equatable, Sendable {
    case began(String)
    case ended(String)
    case queued
  }

  nonisolated let logger = Logger(label: "gated")

  /// Each happening as it happens, in the order it happened, for one test to wait on.
  nonisolated let happenings: AsyncStream<Happening>

  private(set) var events: [Event] = []

  /// Whether the task of each write had been cancelled when the write was let go.
  private(set) var wasCancelled: [String: Bool] = [:]

  private let failing: Set<String>
  private let happening: AsyncStream<Happening>.Continuation
  private var permits = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []

  struct Failure: Error {}

  /// - Parameter failing: The writes that fail when they are let go.
  init(failing: Set<String> = []) {
    self.failing = failing
    (happenings, happening) = AsyncStream.makeStream(of: Happening.self)
  }

  /// How many writes have begun.
  var begun: Int {
    events.count { event in
      if case .began = event {
        true
      } else {
        false
      }
    }
  }

  /// Says a frame was held back to wait its turn: what a writer above this transport is told to
  /// call when it queues one.
  nonisolated func frameQueued() {
    happening.yield(.queued)
  }

  /// Lets the write that has waited longest go.
  func release() {
    if waiting.isEmpty {
      permits += 1
    } else {
      waiting.removeFirst().resume()
    }
  }

  func connect() async throws {}

  func disconnect() async {}

  func send(_ data: Data) async throws {
    let name = String(data: data, encoding: .utf8) ?? ""
    events.append(.began(name))
    happening.yield(.began(name))

    if permits > 0 {
      permits -= 1
    } else {
      await withCheckedContinuation { continuation in
        waiting.append(continuation)
      }
    }

    wasCancelled[name] = Task.isCancelled
    events.append(.ended(name))
    happening.yield(.ended(name))

    if failing.contains(name) {
      throw Failure()
    }
  }

  func receive() -> AsyncThrowingStream<Data, any Error> {
    AsyncThrowingStream { _ in }
  }
}
