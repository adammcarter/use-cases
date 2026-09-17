import Foundation

/// Why a git command could not produce its output.
public enum GitError: Error, Equatable, Sendable {
  /// git exited non-zero, could not be started, or overflowed node's 1 MiB
  /// output buffer. `standardError` is nil when git never ran, and
  /// `description` then carries node's spawn text (`spawnSync git ENOENT`).
  case commandFailed(standardError: String?, description: String)
  /// `git show <ref>:<path>` failed for a reason other than the path being
  /// absent at the ref.
  case baseReferenceUnreadable(message: String)

  public var code: String {
    switch self {
    case .commandFailed: "git_command_failed"
    case .baseReferenceUnreadable: "git_base_reference_unreadable"
    }
  }

  public var standardError: String? {
    if case let .commandFailed(standardError, _) = self {
      standardError
    } else {
      nil
    }
  }

  public var message: String {
    switch self {
    case let .commandFailed(_, description): description
    case let .baseReferenceUnreadable(message): message
    }
  }
}

/// Runs git: the process externality behind the base-ref read and `uc impact`.
public protocol GitRunning: Sendable {
  /// git's stdout as UTF-8 text.
  func run(
    _ arguments: [String],
    workingDirectory: String?,
  ) throws(GitError) -> String
}

/// git through Foundation `Process`, behaving as node's
/// `execFileSync("git", args, { cwd, encoding: "utf8" })` does: `git` found on
/// PATH, a non-zero exit raised with its stderr, stderr also passed through to
/// this process's own, and stdout capped at 1 MiB.
public struct GitProcessRunner: GitRunning {
  /// node's default `maxBuffer`.
  static let maximumOutputBytes = 1024 * 1024

  public init() {}

  public func run(
    _ arguments: [String],
    workingDirectory: String?,
  ) throws(GitError) -> String {
    guard let executable = Self.gitExecutable(),
          workingDirectory.map(Self.isDirectory) ?? true
    else {
      throw .commandFailed(standardError: nil, description: "spawnSync git ENOENT")
    }
    let capture = FileManager.default.temporaryDirectory
      .appendingPathComponent("use-cases-git-\(UUID().uuidString)", isDirectory: true)
    defer {
      try? FileManager.default.removeItem(at: capture)
    }
    let outputs: CapturedProcess
    do {
      outputs = try Self.execute(executable, arguments, workingDirectory, capturingIn: capture)
    } catch {
      throw .commandFailed(standardError: nil, description: "spawnSync git EACCES")
    }
    let standardError = UTF8Text.decodeReplacingInvalid([UInt8](outputs.standardError))
    FileHandle.standardError.write(outputs.standardError)
    guard outputs.standardOutput.count <= Self.maximumOutputBytes else {
      throw .commandFailed(standardError: standardError, description: "spawnSync git ENOBUFS")
    }
    guard outputs.status == 0 else {
      throw .commandFailed(
        standardError: standardError,
        description: "Command failed: git \(arguments.joined(separator: " "))\n\(standardError)",
      )
    }
    return UTF8Text.decodeReplacingInvalid([UInt8](outputs.standardOutput))
  }

  /// Output goes to files rather than pipes, so a large diff can never fill a
  /// pipe buffer and deadlock the wait.
  private static func execute(
    _ executable: URL,
    _ arguments: [String],
    _ workingDirectory: String?,
    capturingIn directory: URL,
  ) throws -> CapturedProcess {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let outputURL = directory.appendingPathComponent("stdout")
    let errorURL = directory.appendingPathComponent("stderr")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)
    FileManager.default.createFile(atPath: errorURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: outputURL)
    let error = try FileHandle(forWritingTo: errorURL)
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    if let workingDirectory {
      process.currentDirectoryURL = URL(fileURLWithPath: workingDirectory, isDirectory: true)
    }
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = error
    try process.run()
    process.waitUntilExit()
    try output.close()
    try error.close()
    return try CapturedProcess(
      standardOutput: Data(contentsOf: outputURL),
      standardError: Data(contentsOf: errorURL),
      status: process.terminationStatus,
    )
  }

  /// The first executable `git` on PATH, as `execFileSync` resolves it.
  private static func gitExecutable() -> URL? {
    let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
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

/// What a finished git process left behind.
private struct CapturedProcess {
  let standardOutput: Data
  let standardError: Data
  let status: Int32
}
