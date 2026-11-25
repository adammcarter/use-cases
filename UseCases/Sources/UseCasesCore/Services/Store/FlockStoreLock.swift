import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Locks with `flock`, which belongs to the open file and so excludes another process and also
/// another open of the same file in this one. (A POSIX record lock belongs to the process, and
/// would let two writers of one process in together.)
struct FlockStoreLock: StoreLocking {
  func locked<Value>(
    at lock: URL,
    perform body: () throws(StoreWritingError) -> Value,
  ) throws(StoreWritingError) -> Value {
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

    // Every way out of here lets go of the lock: unlocked first, for a process being started
    // at this moment may hold a copy of the descriptor, and closing would not release the lock
    // until that process executes.
    defer {
      flock(descriptor, LOCK_UN)
      close(descriptor)
    }

    while flock(descriptor, LOCK_EX) != 0 {
      guard errno == EINTR else {
        throw Self.error(
          at: lock,
          errorNumber: errno,
        )
      }
    }

    return try body()
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
