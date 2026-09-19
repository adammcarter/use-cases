import Foundation

/// The read half of the marker filesystem seam: the TypeScript's
/// `VerificationContextFs`, the read-only subset of `MarkerFs` the verification
/// context hash reads declared inputs and the lockfile through.
public protocol TextFileReading: Sendable {
  /// The file's UTF-8 text, or nil when nothing exists at `path`. Any other
  /// failure is raised.
  func readText(atPath path: String) throws(FileAccessError) -> String?
}

/// The filesystem seam the run-key code reads and writes through: the read and
/// the atomic write of the TypeScript's `MarkerFs`.
public protocol TextFileStoring: TextFileReading {
  /// Replace the file with `text`, creating parent directories, atomically.
  /// With `preservingMode`, the destination's existing permission bits are
  /// carried across the replace; a no-op when the destination does not exist.
  func writeText(
    _ text: String,
    toPath path: String,
    preservingMode: Bool,
  ) throws(FileAccessError)
}

public extension TextFileStoring {
  /// `writeText(path, text)` with no options: the umask default mode.
  func writeText(
    _ text: String,
    toPath path: String,
  ) throws(FileAccessError) {
    try writeText(text, toPath: path, preservingMode: false)
  }
}

/// One entry of `readdirSync(path, { withFileTypes: true })`: what the entry
/// itself is, never what a symlink points at.
public struct MarkerDirectoryEntry: Equatable, Sendable {
  public let name: String
  public let isDirectory: Bool
  public let isFile: Bool
  public let isSymbolicLink: Bool

  public init(
    name: String,
    isDirectory: Bool,
    isFile: Bool,
    isSymbolicLink: Bool,
  ) {
    self.name = name
    self.isDirectory = isDirectory
    self.isFile = isFile
    self.isSymbolicLink = isSymbolicLink
  }
}

/// The whole of the TypeScript's `MarkerFs`: what the marker command cores
/// (bind, unbind, rebind, validate-ledger) touch the filesystem through.
public protocol MarkerFileSystem: TextFileStoring {
  /// `existsSync(path)`.
  func exists(atPath path: String) -> Bool

  /// The directory's entries in libuv's order; a directory that cannot be
  /// listed is raised.
  func listDirectory(atPath path: String) throws(FileAccessError) -> [MarkerDirectoryEntry]
}

/// The real filesystem, failing as node's `fs` fails.
public struct LocalTextFiles: MarkerFileSystem {
  /// `Date.now()`: the milliseconds the temporary file name carries.
  let currentMilliseconds: @Sendable () -> Int

  /// The process's own filesystem. `currentMilliseconds` is the clock the
  /// temporary file name is taken from; the default is the system clock.
  public init(currentMilliseconds: @escaping @Sendable () -> Int = {
    Int(Date().timeIntervalSince1970 * 1000)
  }) {
    self.currentMilliseconds = currentMilliseconds
  }

  public func readText(atPath path: String) throws(FileAccessError) -> String? {
    do throws(FileAccessError) {
      return try NodeFile.readText(atPath: path)
    } catch where error.errorNumber == ENOENT {
      return nil
    }
  }

  /// `mkdirSync(dirname(path), { recursive: true })`; with `preservingMode`,
  /// the destination's `stat` mode (ENOENT tolerated); a write to
  /// `<path>.tmp-<pid>-<ms>`; a `chmod` of it to the preserved mode; then a
  /// rename over `path`.
  public func writeText(
    _ text: String,
    toPath path: String,
    preservingMode: Bool,
  ) throws(FileAccessError) {
    try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(path))
    var preservedMode: mode_t?
    if preservingMode {
      var status = stat()
      if stat(path, &status) == 0 {
        preservedMode = status.st_mode
      } else if errno != ENOENT {
        throw FileAccessError(errorNumber: errno, operation: "stat", path: path)
      }
    }
    let temporaryPath = "\(path).tmp-\(getpid())-\(currentMilliseconds())"
    try NodeFile.writeText(text, atPath: temporaryPath)
    if let preservedMode, chmod(temporaryPath, preservedMode & 0o7777) != 0 {
      throw FileAccessError(errorNumber: errno, operation: "chmod", path: temporaryPath)
    }
    guard rename(temporaryPath, path) == 0 else {
      throw FileAccessError(
        errorNumber: errno,
        operation: "rename",
        path: temporaryPath,
        destination: path,
      )
    }
  }

  public func exists(atPath path: String) -> Bool {
    NodeFile.exists(atPath: path)
  }

  /// `readdirSync(path, { withFileTypes: true })`: libuv's `scandir`, in
  /// `strcmp` order, each entry typed by its `d_type` and by `lstat` only when
  /// the filesystem does not report one — so a symlink is a symlink, never
  /// what it points at.
  public func listDirectory(atPath path: String) throws(FileAccessError) -> [MarkerDirectoryEntry] {
    guard let directory = opendir(path) else {
      throw FileAccessError(errorNumber: errno, operation: "scandir", path: path)
    }
    defer {
      closedir(directory)
    }
    var entries: [MarkerDirectoryEntry] = []
    while let entry = readdir(directory) {
      let name = withUnsafeBytes(of: entry.pointee.d_name) { raw in
        UTF8Text.decodeReplacingInvalid(Array(raw.prefix { byte in
          byte != 0
        }))
      }
      guard name != ".", name != ".." else {
        continue
      }
      let type = Int32(entry.pointee.d_type)
      let resolved = type == DT_UNKNOWN ? Self.entryType(atPath: path + "/" + name) : type
      entries.append(MarkerDirectoryEntry(
        name: name,
        isDirectory: resolved == DT_DIR,
        isFile: resolved == DT_REG,
        isSymbolicLink: resolved == DT_LNK,
      ))
    }
    return entries.sorted { left, right in
      JavaScriptStringOrder.byteAscending(left.name, right.name)
    }
  }

  /// libuv's fallback for an unknown `d_type`: the entry's `lstat` type, or
  /// unknown when it cannot be inspected.
  private static func entryType(atPath path: String) -> Int32 {
    var status = stat()
    guard lstat(path, &status) == 0 else {
      return DT_UNKNOWN
    }
    switch status.st_mode & S_IFMT {
    case S_IFLNK: return DT_LNK
    case S_IFDIR: return DT_DIR
    case S_IFREG: return DT_REG
    default: return DT_UNKNOWN
    }
  }
}
