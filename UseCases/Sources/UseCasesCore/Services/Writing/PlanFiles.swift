import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The system calls a plan is written with, each failing as the plan's own error.
enum PlanFiles {
  /// Who owns a file and what it may do, which a replaced file keeps.
  struct Attributes {
    let permissions: mode_t
    let owner: uid_t
    let group: gid_t
  }

  /// A new file's permissions: runnable when it is a hook, otherwise readable by all.
  static func permissions(isExecutable: Bool) -> mode_t {
    isExecutable ? 0o755 : 0o644
  }

  /// The permissions and owner of the file at `location`.
  static func attributes(of location: URL) throws(PlanWritingError) -> Attributes {
    var information = stat()

    guard stat(location.path, &information) == 0 else {
      throw failure(at: location)
    }

    return Attributes(
      permissions: information.st_mode & 0o7777,
      owner: information.st_uid,
      group: information.st_gid,
    )
  }

  /// Writes `bytes` to a new file beside `target`, flushed and with exactly these permissions,
  /// and gives it the owner when the system allows. Nothing is left behind on a failure.
  static func stage(
    _ bytes: [UInt8],
    beside target: URL,
    permissions: mode_t,
    owner: Attributes? = nil,
  ) throws(PlanWritingError) -> URL {
    let staged = sibling(
      of: target,
      kind: "tmp",
    )

    let descriptor = open(
      staged.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      0o600,
    )
    guard descriptor >= 0 else {
      throw failure(at: staged)
    }

    defer {
      close(descriptor)
    }

    do {
      try fill(
        descriptor,
        with: bytes,
        at: staged,
        permissions: permissions,
        owner: owner,
      )
    } catch {
      discard(staged)

      throw error
    }

    return staged
  }

  /// A name beside `target` that nothing has: the target's folder, so a rename stays on one volume.
  static func sibling(
    of target: URL,
    kind: String,
  ) -> URL {
    target.deletingLastPathComponent()
      .appendingPathComponent(".\(target.lastPathComponent).\(kind)-\(UUID().uuidString)")
  }

  /// Makes `name` another name for `file`; fails when `name` is taken.
  static func addName(
    for file: URL,
    as name: URL,
  ) throws(PlanWritingError) {
    guard link(file.path, name.path) == 0 else {
      throw failure(at: name)
    }
  }

  /// Renames `file` to `destination`, replacing what is at `destination`.
  static func move(
    _ file: URL,
    to destination: URL,
  ) throws(PlanWritingError) {
    guard rename(file.path, destination.path) == 0 else {
      throw failure(at: destination)
    }
  }

  /// Takes a name away. A name that is already gone is fine.
  static func dropName(_ file: URL) throws(PlanWritingError) {
    guard unlink(file.path) == 0 || errno == ENOENT else {
      throw failure(at: file)
    }
  }

  /// Takes a name away, and says nothing if it cannot: for what a failed write leaves behind.
  static func discard(_ file: URL) {
    _ = unlink(file.path)
  }

  /// Makes a folder. `true` when it is new; a folder that is there is `false`.
  static func makeFolder(_ folder: URL) throws(PlanWritingError) -> Bool {
    if mkdir(folder.path, 0o755) == 0 {
      return true
    }

    guard errno == EEXIST else {
      throw failure(at: folder)
    }

    return false
  }

  /// Takes away a folder that is empty, and says nothing if it cannot.
  static func removeFolder(_ folder: URL) {
    _ = rmdir(folder.path)
  }

  /// Flushes the names in a folder, so that a rename survives a crash.
  static func flushFolder(_ folder: URL) {
    let descriptor = open(
      folder.path,
      O_RDONLY | O_CLOEXEC,
    )
    guard descriptor >= 0 else {
      return
    }

    defer {
      close(descriptor)
    }

    _ = fsync(descriptor)
  }

  private static func fill(
    _ descriptor: Int32,
    with bytes: [UInt8],
    at file: URL,
    permissions: mode_t,
    owner: Attributes?,
  ) throws(PlanWritingError) {
    var written = 0

    while written < bytes.count {
      let count = bytes[written...].withUnsafeBytes { buffer in
        write(descriptor, buffer.baseAddress, buffer.count)
      }

      if count < 0 {
        guard errno == EINTR else {
          throw failure(at: file)
        }
        continue
      }

      written += count
    }

    // Exactly the permissions asked for, whatever the umask says.
    guard fchmod(descriptor, permissions) == 0 else {
      throw failure(at: file)
    }

    // Giving a file to its owner is only for a process allowed to: the rest keeps its own.
    if let owner {
      _ = fchown(descriptor, owner.owner, owner.group)
    }

    guard flush(descriptor) else {
      throw failure(at: file)
    }
  }

  private static func flush(_ descriptor: Int32) -> Bool {
    #if canImport(Darwin)
      // On a Mac `fsync` leaves the bytes in the drive's cache; where the drive cannot be told to
      // flush it, `fsync` is the most there is.
      if fcntl(descriptor, F_FULLFSYNC) == 0 {
        return true
      }
    #endif

    return fsync(descriptor) == 0
  }

  static func failure(at location: URL) -> PlanWritingError {
    .unwritable(
      location: location.path,
      reason: String(cString: strerror(errno)),
    )
  }
}
