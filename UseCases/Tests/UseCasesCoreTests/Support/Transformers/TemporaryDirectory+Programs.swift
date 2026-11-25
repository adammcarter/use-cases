import Foundation

extension TemporaryDirectory {
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
      ofItemAtPath: location(of: path).path,
    )
  }

  /// What a file below this folder holds.
  func text(of path: String) throws -> String {
    try String(
      contentsOf: location(of: path),
      encoding: .utf8,
    )
  }

  /// Whether anything is at this path.
  func exists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: location(of: path).path)
  }
}
