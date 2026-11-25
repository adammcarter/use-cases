import Foundation
import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A run opened to be held is locked before anyone can see it (chapter 12 §18, chapter 13 §7).
struct RunWriterHeldOpeningTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  /// Whether another open of the run's lock file is refused, as a second process's would be.
  private static func isHeld(by folder: URL) -> Bool {
    let descriptor = open(
      folder.appendingPathComponent(StoreLayout.runLockFile).path,
      O_RDWR | O_CREAT | O_CLOEXEC,
      0o644,
    )

    guard descriptor >= 0 else {
      return false
    }

    defer {
      close(descriptor)
    }

    return flock(descriptor, LOCK_EX | LOCK_NB) != 0 && errno == EWOULDBLOCK
  }

  /// A writer that asks, the moment a run is published, whether its lock is held, and writes the
  /// answer, `held` or `free`, to `answer`.
  private func writer() throws -> RunWriter {
    let answer = directory.location(of: Self.answerFile)

    return try RunWriter(
      clock: FixedTimekeeper(),
      random: FixedRandomBits(),
      files: PausingFileWriter { folder in
        try? Data((Self.isHeld(by: folder) ? "held" : "free").utf8).write(to: answer)
      },
    )
  }

  private static let answerFile = "answer.txt"

  /// What the writer saw when the run was published.
  private func seen() throws -> String {
    try String(
      contentsOf: directory.location(of: Self.answerFile),
      encoding: .utf8,
    )
  }

  @Test
  func `a held verify run is locked the moment it is published`() throws {
    let held = try writer().openHeldVerifyRun(
      StartDraft.sample(),
      in: directory.url,
    )

    defer {
      held.lock.release()
    }

    #expect(try seen() == "held")
  }

  @Test
  func `a held record run is locked the moment it is published`() throws {
    let held = try writer().openHeldRun(
      kind: .record,
      in: directory.url,
    )

    defer {
      held.lock.release()
    }

    #expect(try seen() == "held")
  }

  @Test
  func `a run opened without being held is not locked`() throws {
    _ = try writer().openVerifyRun(
      StartDraft.sample(),
      in: directory.url,
    )

    #expect(try seen() == "free")
  }

  @Test
  func `the held lock is the run's own, and releasing it frees the run`() async throws {
    let writer = try RunWriter(
      clock: FixedTimekeeper(),
      random: FixedRandomBits(),
    )
    let held = try writer.openHeldVerifyRun(
      StartDraft.sample(),
      in: directory.url,
    )
    let folder = directory.location(of: ".use-cases/runs/\(held.run.identifier.text)")

    let whileHeld = try await FlockRunLock().holding(run: folder) { true }
    held.lock.release()
    let afterwards = try await FlockRunLock().holding(run: folder) { true }

    #expect(whileHeld == nil)
    #expect(afterwards == true)
  }

  @Test
  func `a run that cannot be published leaves no lock held`() throws {
    let locks = OutsideRunLock(lockFile: directory.location(of: "outside.lock"))
    let failing = try RunWriter(
      clock: FixedTimekeeper(),
      random: FixedRandomBits(),
      files: PublishFailingFileWriter(),
      runLocks: locks,
    )

    #expect(throws: StoreWritingError.self) {
      try failing.openHeldVerifyRun(
        StartDraft.sample(),
        in: directory.url,
      )
    }
    #expect(locks.isFree)
  }

  @Test
  func `the lock double really is held while a run is open`() throws {
    let locks = OutsideRunLock(lockFile: directory.location(of: "outside.lock"))
    let writer = try RunWriter(
      clock: FixedTimekeeper(),
      random: FixedRandomBits(),
      runLocks: locks,
    )

    let held = try writer.openHeldVerifyRun(
      StartDraft.sample(),
      in: directory.url,
    )

    #expect(!locks.isFree)
    held.lock.release()
    #expect(locks.isFree)
  }
}
