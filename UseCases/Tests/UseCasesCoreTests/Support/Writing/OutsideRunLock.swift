import Foundation
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A run lock taken on a file of the test's own instead of one inside the run's folder, so that
/// whether it is still held can be asked after the run's folder is gone.
struct OutsideRunLock: RunLocking {
  let lockFile: URL

  /// Whether nobody holds the lock: another open of the file can take it.
  var isFree: Bool {
    let descriptor = open(lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)

    guard descriptor >= 0 else {
      return false
    }

    defer {
      close(descriptor)
    }

    return flock(descriptor, LOCK_EX | LOCK_NB) == 0
  }

  func holding<Value>(
    run: URL,
    perform body: () async -> Value,
  ) async throws(StoreWritingError) -> Value? {
    await body()
  }

  func acquire(run: URL) throws(StoreWritingError) -> HeldRunLock? {
    let descriptor = open(lockFile.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)

    guard descriptor >= 0, flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      return nil
    }

    return HeldRunLock(descriptor: descriptor)
  }
}
