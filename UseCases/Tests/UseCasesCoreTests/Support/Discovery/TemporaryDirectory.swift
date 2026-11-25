import Foundation
@testable import UseCasesCore

/// A real folder on disk for one test, removed when the test lets go of it.
final class TemporaryDirectory {
  /// The canonical location, symlinks resolved as the core resolves them.
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-tests-\(UUID().uuidString)")

    try FileManager.default.createDirectory(
      at: base,
      withIntermediateDirectories: true,
    )

    url = LocalFileSystem().canonicalLocation(of: base)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// Where a path below this folder is.
  func location(of path: String) -> URL {
    // Built from text, so it never gains the trailing slash that appending to a folder can add.
    URL(
      fileURLWithPath: "\(url.path)/\(path)",
      isDirectory: false,
    )
  }

  /// Writes a file, making the folders above it.
  func write(
    _ path: String,
    _ text: String = "",
  ) throws {
    let file = location(of: path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    try Data(text.utf8).write(to: file)
  }

  /// Writes bytes that need not be text.
  func write(
    _ path: String,
    bytes: [UInt8],
  ) throws {
    let file = location(of: path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    try Data(bytes).write(to: file)
  }

  func makeDirectory(_ path: String) throws {
    try FileManager.default.createDirectory(
      at: location(of: path),
      withIntermediateDirectories: true,
    )
  }

  /// Makes a real symlink at `path` that points to `target`, as written (relative targets stay
  /// relative to the link's folder).
  func symlink(
    _ path: String,
    to target: String,
  ) throws {
    let link = location(of: path)

    try FileManager.default.createDirectory(
      at: link.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    try FileManager.default.createSymbolicLink(
      atPath: link.path,
      withDestinationPath: target,
    )
  }

  /// Makes a named pipe. Opening one for reading blocks until something writes to it, so a test
  /// that finishes proves the code under test never opened it.
  func makeFIFO(_ path: String) throws {
    let pipe = location(of: path)

    try FileManager.default.createDirectory(
      at: pipe.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    guard mkfifo(pipe.path, 0o644) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  /// Makes a file whose name is these bytes, whatever they are. Returns `false` when the file
  /// system refuses the name, as APFS does for a name that is not UTF-8.
  func makeFile(
    namedByBytes name: [UInt8],
    in folder: String,
  ) throws -> Bool {
    try makeDirectory(folder)

    let path = Array(location(of: folder).path.utf8) + [0x2F] + name + [0]
    let descriptor = creat(
      path.map(CChar.init(bitPattern:)),
      0o644,
    )

    guard descriptor >= 0 else {
      return false
    }

    close(descriptor)

    return true
  }

  /// Makes a folder whose name is these bytes, whatever they are. Returns `false` when the file
  /// system refuses the name.
  func makeDirectory(
    namedByBytes name: [UInt8],
    in folder: String,
  ) throws -> Bool {
    try makeDirectory(folder)

    let path = Array(location(of: folder).path.utf8) + [0x2F] + name + [0]
    let made = mkdir(
      path.map(CChar.init(bitPattern:)),
      0o755,
    )

    return made == 0
  }

  /// Writes an empty file called `name` in the folder called these bytes inside `folder`.
  func makeFile(
    named name: String,
    inFolderNamedByBytes bytes: [UInt8],
    in folder: String,
  ) -> Bool {
    let path = Array(location(of: folder).path.utf8) + [0x2F] + bytes + [0x2F] + Array(name.utf8) +
      [0]
    let descriptor = creat(
      path.map(CChar.init(bitPattern:)),
      0o644,
    )

    guard descriptor >= 0 else {
      return false
    }

    close(descriptor)

    return true
  }
}
