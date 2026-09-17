import Foundation

/// The filesystem seam the run-key code reads and writes through: exactly the
/// two operations it uses of the TypeScript's `MarkerFs`.
public protocol TextFileStoring: Sendable {
  /// The file's UTF-8 text, or nil when nothing exists at `path`. Any other
  /// failure is raised.
  func readText(atPath path: String) throws(FileAccessError) -> String?

  /// Replace the file with `text`, creating parent directories, atomically.
  func writeText(
    _ text: String,
    toPath path: String,
  ) throws(FileAccessError)
}

/// The real filesystem, failing as node's `fs` fails.
public struct LocalTextFiles: TextFileStoring {
  /// Nothing to configure: the process's own filesystem.
  public init() {}

  public func readText(atPath path: String) throws(FileAccessError) -> String? {
    do throws(FileAccessError) {
      return try NodeFile.readText(atPath: path)
    } catch where error.errorNumber == ENOENT {
      return nil
    }
  }

  /// `mkdirSync(dirname(path), { recursive: true })`, a write to
  /// `<path>.tmp-<pid>-<ms>`, then a rename over `path`.
  public func writeText(
    _ text: String,
    toPath path: String,
  ) throws(FileAccessError) {
    try NodeFile.makeDirectories(atPath: WorkspacePath.dirname(path))
    let milliseconds = Int(Date().timeIntervalSince1970 * 1000)
    let temporaryPath = "\(path).tmp-\(getpid())-\(milliseconds)"
    try NodeFile.writeText(text, atPath: temporaryPath)
    guard rename(temporaryPath, path) == 0 else {
      throw FileAccessError(
        errorNumber: errno,
        operation: "rename",
        path: temporaryPath,
        destination: path,
      )
    }
  }
}
