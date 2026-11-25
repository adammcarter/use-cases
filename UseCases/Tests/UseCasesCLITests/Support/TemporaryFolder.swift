import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A real folder for one test, removed when the test lets go of it.
final class TemporaryFolder {
  let url: URL

  init() throws {
    let base = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-cli-tests-\(UUID().uuidString)")

    try FileManager.default.createDirectory(
      at: base,
      withIntermediateDirectories: true,
    )

    // The system's own spelling of the folder, so paths compare equal after symlinks resolve.
    url = base.resolvingSymlinksInPath()
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }

  /// Writes a program the core can start: a shell script, executable.
  func writeProgram(
    _ path: String,
    _ body: String,
  ) throws {
    try write(
      path,
      "#!/bin/sh\n\(body)",
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: url.appendingPathComponent(path).path,
    )
  }

  /// Makes a named pipe, which a copy of the folder cannot hold.
  func makeFIFO(_ path: String) throws {
    guard mkfifo(url.appendingPathComponent(path).path, 0o644) == 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
  }

  func write(
    _ path: String,
    _ text: String,
  ) throws {
    let file = url.appendingPathComponent(path)

    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(),
      withIntermediateDirectories: true,
    )

    try Data(text.utf8).write(to: file)
  }
}
