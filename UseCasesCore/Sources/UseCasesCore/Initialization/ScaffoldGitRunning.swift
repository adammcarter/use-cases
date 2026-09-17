import Foundation

/// What `spawnSync("git", ...)` reports back to init.
public struct ScaffoldGitOutcome: Sendable, Equatable {
  /// The exit status, or nil when git never ran (`status: null`).
  public let exitStatus: Int32?

  /// Everything git wrote to stdout, as UTF-8 text.
  public let standardOutput: String
}

/// Runs git for init: the process externality behind the repository check,
/// the `core.hooksPath` read and its write.
public protocol ScaffoldGitRunning: Sendable {
  func run(
    _ arguments: [String],
    workingDirectory: String,
  ) -> ScaffoldGitOutcome
}

/// git through Foundation `Process`, behaving as node's
/// `spawnSync("git", args, { cwd })` does for init: `git` found on the
/// environment's PATH, stdout captured, stderr captured and never shown, and a
/// git that cannot start reported as no exit status at all rather than thrown.
public struct ScaffoldGitProcessRunner: ScaffoldGitRunning {
  let environment: [String: String]

  /// `environment` is what git runs with, and whose PATH finds it.
  public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
    self.environment = environment
  }

  public func run(
    _ arguments: [String],
    workingDirectory: String,
  ) -> ScaffoldGitOutcome {
    let neverRan = ScaffoldGitOutcome(exitStatus: nil, standardOutput: "")
    guard let executable = gitExecutable(), Self.isDirectory(workingDirectory) else {
      return neverRan
    }
    let capture = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-init-git-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: capture)
    }
    do {
      return try execute(executable, arguments, workingDirectory, capturingIn: capture)
    } catch {
      return neverRan
    }
  }

  /// Output goes to a file rather than a pipe, so git can never fill a pipe
  /// buffer and deadlock the wait.
  private func execute(
    _ executable: URL,
    _ arguments: [String],
    _ workingDirectory: String,
    capturingIn directory: URL,
  ) throws -> ScaffoldGitOutcome {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let outputURL = directory.appendingPathComponent("stdout")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    process.environment = environment
    process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()
    try output.close()
    let standardOutput = try Data(contentsOf: outputURL)
    return ScaffoldGitOutcome(
      exitStatus: process.terminationStatus,
      standardOutput: UTF8Text.decodeReplacingInvalid([UInt8](standardOutput)),
    )
  }

  /// The first executable `git` on PATH, as libuv resolves it: `/usr/bin:/bin`
  /// when PATH is unset.
  private func gitExecutable() -> URL? {
    let path = environment["PATH"] ?? "/usr/bin:/bin"
    return path
      .split(separator: ":", omittingEmptySubsequences: true)
      .map { directory in
        URL(fileURLWithPath: String(directory)).appendingPathComponent("git")
      }
      .first { candidate in
        FileManager.default.isExecutableFile(atPath: candidate.path)
      }
  }

  private static func isDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
      && isDirectory.boolValue
  }
}
