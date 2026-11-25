import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Writes the store on the machine's file system with POSIX calls.
struct LocalStoreFileWriter: StoreFileWriting {
  static let filePermissions: mode_t = 0o644
  private static let executablePermissions: mode_t = 0o755
  private static let folderPermissions: mode_t = 0o755

  func ensureFolder(at folder: URL) throws(StoreWritingError) {
    if mkdir(folder.path, Self.folderPermissions) == 0 {
      // The new name is in its parent: flush that, or a crash can take the folder with it.
      try flushFolder(at: folder.deletingLastPathComponent())

      return
    }

    let failure = errno
    var status = stat()

    guard failure == EEXIST, lstat(folder.path, &status) == 0 else {
      throw Self.error(
        at: folder,
        errorNumber: failure,
      )
    }

    switch status.st_mode & S_IFMT {
    case S_IFDIR:
      return
    case S_IFLNK:
      throw StoreWritingError.unwritable(
        location: folder.path,
        reason: "it is a symlink, not a folder",
      )
    default:
      throw StoreWritingError.unwritable(
        location: folder.path,
        reason: "it is a file, not a folder",
      )
    }
  }

  func createFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try createFile(
      bytes,
      at: file,
      permissions: Self.filePermissions,
    )
  }

  private func createFile(
    _ bytes: [UInt8],
    at file: URL,
    permissions: mode_t,
  ) throws(StoreWritingError) {
    let descriptor = open(
      file.path,
      O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
      permissions,
    )
    guard descriptor >= 0 else {
      throw Self.error(
        at: file,
        errorNumber: errno,
      )
    }

    defer {
      close(descriptor)
    }

    try Self.writeAll(
      bytes,
      to: descriptor,
      at: file,
    )
    try Self.flush(
      descriptor,
      at: file,
    )
  }

  func replaceFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    let temporary = Self.temporary(beside: file)

    try createFile(
      bytes,
      at: temporary,
    )

    guard rename(temporary.path, file.path) == 0 else {
      let failure = errno
      discard(temporary)

      throw Self.error(
        at: file,
        errorNumber: failure,
      )
    }

    try flushFolder(at: file.deletingLastPathComponent())
  }

  func append(
    _ bytes: [UInt8],
    to file: URL,
  ) throws(StoreWritingError) {
    let descriptor = open(
      file.path,
      O_WRONLY | O_APPEND | O_CLOEXEC,
    )
    guard descriptor >= 0 else {
      throw Self.error(
        at: file,
        errorNumber: errno,
      )
    }

    defer {
      close(descriptor)
    }

    try Self.writeAll(
      bytes,
      to: descriptor,
      at: file,
    )
    try Self.flush(
      descriptor,
      at: file,
    )
  }

  func publishFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try publish(
      bytes,
      at: file,
      permissions: Self.filePermissions,
    )
  }

  func publishExecutableFile(
    _ bytes: [UInt8],
    at file: URL,
  ) throws(StoreWritingError) {
    try publish(
      bytes,
      at: file,
      permissions: Self.executablePermissions,
    )
  }

  private func publish(
    _ bytes: [UInt8],
    at file: URL,
    permissions: mode_t,
  ) throws(StoreWritingError) {
    let temporary = Self.temporary(beside: file)

    try createFile(
      bytes,
      at: temporary,
      permissions: permissions,
    )

    // `link` fails when the name is taken, which `rename` would silently overwrite.
    guard link(temporary.path, file.path) == 0 else {
      let failure = errno
      discard(temporary)

      throw Self.error(
        at: file,
        errorNumber: failure,
      )
    }

    discard(temporary)
    try flushFolder(at: file.deletingLastPathComponent())
  }

  func publishFolder(
    _ folder: URL,
    as published: URL,
  ) throws(StoreWritingError) {
    var status = stat()

    // `rename` over an empty folder succeeds, so a name that is taken is looked for first.
    guard lstat(published.path, &status) != 0, errno == ENOENT else {
      throw StoreWritingError.unwritable(
        location: published.path,
        reason: "it already exists",
      )
    }
    guard rename(folder.path, published.path) == 0 else {
      throw Self.error(
        at: published,
        errorNumber: errno,
      )
    }

    try flushFolder(at: published.deletingLastPathComponent())
  }

  func discard(_ item: URL) {
    try? FileManager.default.removeItem(at: item)
  }

  func flushFolder(at folder: URL) throws(StoreWritingError) {
    let descriptor = open(
      folder.path,
      O_RDONLY | O_CLOEXEC,
    )
    guard descriptor >= 0 else {
      throw Self.error(
        at: folder,
        errorNumber: errno,
      )
    }

    defer {
      close(descriptor)
    }

    try Self.flush(
      descriptor,
      at: folder,
    )
  }

  private static func temporary(beside file: URL) -> URL {
    file.deletingLastPathComponent()
      .appendingPathComponent(".\(file.lastPathComponent).tmp-\(UUID().uuidString)")
  }

  static func writeAll(
    _ bytes: [UInt8],
    to descriptor: Int32,
    at file: URL,
  ) throws(StoreWritingError) {
    var written = 0

    while written < bytes.count {
      let count = bytes[written...].withUnsafeBytes { buffer in
        write(descriptor, buffer.baseAddress, buffer.count)
      }

      if count < 0 {
        guard errno == EINTR else {
          throw error(
            at: file,
            errorNumber: errno,
          )
        }
        continue
      }

      written += count
    }
  }

  static func flush(
    _ descriptor: Int32,
    at file: URL,
  ) throws(StoreWritingError) {
    #if canImport(Darwin)
      // On a Mac `fsync` leaves the bytes in the drive's cache. Where the drive cannot be told
      // to flush it (a folder, some volumes), `fsync` is the most there is.
      if fcntl(descriptor, F_FULLFSYNC) == 0 {
        return
      }
    #endif

    guard fsync(descriptor) == 0 else {
      throw error(
        at: file,
        errorNumber: errno,
      )
    }
  }

  static func error(
    at file: URL,
    errorNumber: Int32,
  ) -> StoreWritingError {
    .unwritable(
      location: file.path,
      reason: String(cString: strerror(errorNumber)),
    )
  }
}
