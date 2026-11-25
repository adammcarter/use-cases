#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The lock of one run, held by the process that made the run or took it up (chapter 12 §18). It
/// is the open file the lock belongs to, so it stays held across the rename that publishes the
/// run's folder, and it dies with the process.
struct HeldRunLock: Equatable, Sendable {
  let descriptor: Int32

  /// Lets go of the lock. Call it once, when the request is done with the run.
  ///
  /// The lock is unlocked before the file is closed. A lock belongs to the open file, not to this
  /// descriptor, so a process being started at that moment may hold a copy of the descriptor until
  /// it executes: closing alone would leave the run locked for as long as that takes.
  func release() {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
