import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The hold one writer has on a workspace while it checks and changes its files, so that two
/// writers never work on it at once. It is a lock on a file in the workspace's `.use-cases/`
/// folder, which is made if it is absent and is never inside the authored tree. The lock goes when
/// the hold is released or the process ends, whatever the way.
struct WriteLock {
  /// The folder, below the workspace root, that holds the lock file.
  static let folderName = ".use-cases"

  /// The lock file's name.
  static let fileName = "write.lock"

  private let descriptor: Int32

  /// Waits for the lock on the workspace and takes it.
  static func acquire(in workspace: URL) throws(PlanWritingError) -> WriteLock {
    let folder = workspace.appendingPathComponent(folderName)
    _ = try PlanFiles.makeFolder(folder)

    let file = folder.appendingPathComponent(fileName)
    let descriptor = open(
      file.path,
      O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW,
      0o644,
    )

    guard descriptor >= 0 else {
      throw PlanFiles.failure(at: file)
    }

    while flock(descriptor, LOCK_EX) != 0 {
      guard errno == EINTR else {
        let failure = PlanFiles.failure(at: file)
        close(descriptor)

        throw failure
      }
    }

    return WriteLock(descriptor: descriptor)
  }

  /// Gives the lock up.
  func release() {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
