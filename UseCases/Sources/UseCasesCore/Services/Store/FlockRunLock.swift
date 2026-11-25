import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Locks a run with a non-blocking `flock` on a file in its folder. The lock belongs to the open
/// file, so it excludes another process and also another open of the same file in this one, and
/// it dies with the process (a crashed finish leaves nothing behind that needs clearing).
struct FlockRunLock: RunLocking {
  func holding<Value>(
    run: URL,
    perform body: () async -> Value,
  ) async throws(StoreWritingError) -> Value? {
    guard let held = try acquire(run: run) else {
      return nil
    }

    // Closing the file releases the lock, so every way out of here lets go of it.
    defer {
      held.release()
    }

    return await body()
  }

  func acquire(run: URL) throws(StoreWritingError) -> HeldRunLock? {
    let lock = run.appendingPathComponent(StoreLayout.runLockFile)
    let descriptor = open(
      lock.path,
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      0o644,
    )
    guard descriptor >= 0 else {
      throw Self.error(
        at: lock,
        errorNumber: errno,
      )
    }

    while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      let failure = errno

      switch failure {
      case EINTR:
        continue
      case EWOULDBLOCK, EAGAIN:
        close(descriptor)

        return nil
      default:
        close(descriptor)

        throw Self.error(
          at: lock,
          errorNumber: failure,
        )
      }
    }

    // The file is opened close-on-exec, so a process the request starts never inherits the lock.
    return HeldRunLock(descriptor: descriptor)
  }

  private static func error(
    at file: URL,
    errorNumber: Int32,
  ) -> StoreWritingError {
    .unwritable(
      location: file.path,
      reason: String(cString: strerror(errorNumber)),
    )
  }
}
