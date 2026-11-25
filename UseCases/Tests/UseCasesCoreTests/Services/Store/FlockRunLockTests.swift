import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

private actor Suspension {
  private var count = 0

  func suspend() {
    count += 1
  }
}

struct FlockRunLockTests {
  private let directory: TemporaryDirectory
  private let lock = FlockRunLock()

  init() throws {
    directory = try TemporaryDirectory()
    try directory.makeDirectory("run")
  }

  private var run: URL {
    directory.location(of: "run")
  }

  /// Whether the lock of the run can be had right now; the answer is `false` when another holder
  /// has it.
  private func canHold() async -> Bool {
    let held = try? await lock.holding(run: run) {
      true
    }

    return held ?? false
  }

  @Test
  func `the body runs with the lock held, and its answer comes back`() async throws {
    let answer = try await lock.holding(run: run) {
      42
    }

    #expect(answer == 42)
  }

  @Test
  func `the lock file is called .lock and sits at the root of the run`() async throws {
    _ = try await lock.holding(run: run) {
      await canHold()
    }

    #expect(try FileManager.default.contentsOfDirectory(atPath: run.path) == [".lock"])
  }

  @Test
  func `a second holder is refused at once and its body never runs`() async throws {
    let inner = try await lock.holding(run: run) {
      await canHold()
    }

    #expect(inner == false)
  }

  @Test
  func `the lock is free again when the body has ended`() async throws {
    _ = try await lock.holding(run: run) {
      1
    }

    #expect(await canHold())
  }

  @Test
  func `a copy of the descriptor that outlives the release does not keep the lock`() async throws {
    let held = try #require(try lock.acquire(run: run))
    // What a process being started holds, until it executes, of every descriptor this one has.
    let copy = dup(held.descriptor)
    defer {
      close(copy)
    }

    held.release()

    #expect(await canHold())
  }

  @Test
  func `a body that waits keeps the lock across awaits`() async throws {
    let inner = try await lock.holding(run: run) {
      // A real suspension while the lock is held: the body resumes after an await on an actor.
      await Suspension().suspend()

      return await canHold()
    }

    #expect(inner == false)
  }

  @Test
  func `a run folder that is not there cannot be locked`() async {
    await #expect(throws: StoreWritingError.self) {
      try await lock.holding(run: directory.location(of: "missing")) {
        1
      }
    }
  }
}
