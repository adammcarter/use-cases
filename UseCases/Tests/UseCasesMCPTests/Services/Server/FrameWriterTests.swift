import Foundation
import Testing
@testable import UseCasesMCP

struct FrameWriterTests {
  /// A writer over `inner` that tells `inner` of each frame it holds back, so a test waits on
  /// the frame being queued and not on a count.
  private func writer(over inner: GatedTransport) -> FrameWriter {
    FrameWriter(
      transport: inner,
      onQueued: {
        inner.frameQueued()
      },
    )
  }

  @Test
  func `a frame is not begun until the one before it has been written to its end`() async throws {
    let inner = GatedTransport()
    let writer = writer(over: inner)
    var happenings = inner.happenings.makeAsyncIterator()

    let first = Task {
      try await writer.write(Data("A".utf8))
    }
    let firstSeen = await happenings.next()
    let second = Task {
      try await writer.write(Data("B".utf8))
    }
    // The first is still being written, so the second is held back: queued, not begun.
    let secondSeen = await happenings.next()
    await inner.release()
    await inner.release()
    try await first.value
    try await second.value

    #expect(firstSeen == .began("A"))
    #expect(secondSeen == .queued)
    #expect(
      await inner.events == [.began("A"), .ended("A"), .began("B"), .ended("B")],
    )
  }

  @Test
  func `many frames are written in the order they were asked for, each whole`() async throws {
    let inner = GatedTransport()
    let writer = writer(over: inner)
    var happenings = inner.happenings.makeAsyncIterator()
    var names: [String] = []
    var expected: [GatedTransport.Event] = []

    for number in 0 ..< 8 {
      names.append("frame-\(number)")
      expected += [.began("frame-\(number)"), .ended("frame-\(number)")]
    }

    var writes: [Task<Void, any Error>] = []
    var seen: [GatedTransport.Happening?] = []

    for name in names {
      writes.append(
        Task {
          try await writer.write(Data(name.utf8))
        },
      )
      // The first is still being written, so each after it is held back: queued, not begun.
      await seen.append(happenings.next())
    }

    for _ in names {
      await inner.release()
    }

    for write in writes {
      try await write.value
    }

    #expect(seen == [.began("frame-0")] + Array(repeating: .queued, count: 7))
    #expect(await inner.events == expected)
  }

  @Test
  func `a frame that cannot be written throws why, and the next frame still has its turn`(
  ) async throws {
    let inner = GatedTransport(failing: ["A"])
    let writer = writer(over: inner)
    var happenings = inner.happenings.makeAsyncIterator()
    await inner.release()
    await inner.release()

    await #expect(throws: GatedTransport.Failure.self) {
      try await writer.write(Data("A".utf8))
    }
    #expect(await happenings.next() == .began("A"))
    #expect(await happenings.next() == .ended("A"))
    let second = Task {
      try await writer.write(Data("B".utf8))
    }
    // The failed frame gave up its turn, so the next one begins at once rather than being queued.
    let turn = await happenings.next()
    try #require(turn == .began("B"))
    try await second.value

    #expect(await inner.events.contains(.ended("B")))
  }

  @Test
  func `the call that asked for a frame being cancelled does not cut the frame short`(
  ) async throws {
    let inner = GatedTransport()
    let writer = writer(over: inner)
    var happenings = inner.happenings.makeAsyncIterator()

    let write = Task {
      try await writer.write(Data("A".utf8))
    }
    #expect(await happenings.next() == .began("A"))
    write.cancel()
    await inner.release()
    try await write.value

    #expect(await inner.wasCancelled["A"] == false)
  }
}
