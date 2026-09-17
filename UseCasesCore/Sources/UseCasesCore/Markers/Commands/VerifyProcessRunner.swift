import Foundation

/// The verifier as a real process, behaving as the TypeScript's
/// `spawnSync(command[0], command.slice(1), { cwd, encoding: "utf8", timeout })`
/// does, measured against node on this machine:
///
/// - no shell; the program is found as `execvp` finds it: a name holding a `/`
///   is a path (relative to `cwd`), anything else is looked up on the inherited
///   `PATH`, whose relative entries are also relative to `cwd`;
/// - the environment is inherited and stdin reads as empty;
/// - a program that cannot be started (absent, not executable, a directory, or
///   a `cwd` that is not a directory) exits 1 with no output;
/// - past the timeout the child gets SIGTERM, reading stops, and the result is
///   timed out — exit 124, unless the child still exits with a status of its
///   own; a timeout of 0 is no timeout;
/// - stdout and stderr TOGETHER are capped at node's 1 MiB `maxBuffer`: the read
///   that crosses it is kept, the child gets SIGTERM, and it exits 1;
/// - a child killed by any signal other than the timeout's exits 1;
/// - the bytes are decoded once, at the end, as UTF-8 with each maximal invalid
///   subpart replaced by U+FFFD.
///
/// It waits for both pipes to close, not just for the child: a grandchild that
/// keeps stdout open keeps the run open, as it does in node.
///
/// One thread, no concurrency: both pipes are read in a `poll(2)` loop whose
/// wait is bounded by the deadline, so neither pipe can fill and block the
/// child while the other is being waited on.
public struct VerifyProcessRunner: VerifySpawnRunning {
  /// node's default `maxBuffer`, shared by stdout and stderr.
  static let maximumOutputBytes = 1024 * 1024
  /// JavaScript's `Number.MAX_SAFE_INTEGER`.
  private static let largestTimeoutMilliseconds = 9_007_199_254_740_991.0
  static let readChunkBytes = 64 * 1024

  public init() {}

  public func run(_ request: VerifySpawnRequest) throws(VerifySpawnError) -> VerifySpawnResult {
    let timeoutMilliseconds = try Self.validate(request)
    guard let child = Self.launch(request) else {
      return VerifySpawnResult(exitCode: 1, timedOut: false, standardOutput: "", standardError: "")
    }
    let process = child.process
    var capture = OutputCapture(
      descriptors: [
        child.output.fileHandleForReading.fileDescriptor,
        child.error.fileHandleForReading.fileDescriptor,
      ],
      deadline: timeoutMilliseconds.map { milliseconds in
        ContinuousClock.now + .milliseconds(Int64(milliseconds))
      },
    )
    let ending = capture.drain()
    if ending != .finished, process.isRunning {
      kill(process.processIdentifier, SIGTERM)
    }
    try? child.output.fileHandleForReading.close()
    try? child.error.fileHandleForReading.close()
    // Always reaped before its status is read; the deadline can still pass
    // while a child that closed its pipes runs on.
    let exitedInTime = capture.waitForExit(process, killOnDeadline: ending == .finished)
    let timedOut = ending == .timedOut || !exitedInTime
    return VerifySpawnResult(
      exitCode: process.terminationReason == .exit
        ? Int(process.terminationStatus)
        : timedOut ? 124 : 1,
      timedOut: timedOut,
      standardOutput: UTF8Text.decodeReplacingInvalid(capture.buffers[0]),
      standardError: UTF8Text.decodeReplacingInvalid(capture.buffers[1]),
    )
  }

  /// The started child and its stdout and stderr pipes, or nil when it could
  /// not be started. Pipes, not raw descriptors: `Process` owns the parent's
  /// write ends and closes them itself.
  private static func launch(_ request: VerifySpawnRequest) -> LaunchedChild? {
    guard isDirectory(request.workingDirectory),
          let executable = executable(
            request.command[0],
            workingDirectory: request.workingDirectory,
          )
    else {
      return nil
    }
    let output = Pipe()
    let error = Pipe()
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = Array(request.command.dropFirst())
    process.currentDirectoryURL = URL(fileURLWithPath: request.workingDirectory, isDirectory: true)
    process.standardInput = FileHandle.nullDevice
    process.standardOutput = output
    process.standardError = error
    do {
      try process.run()
    } catch {
      return nil
    }
    return LaunchedChild(process: process, output: output, error: error)
  }

  /// node's argument checks, in its order; the timeout in milliseconds, or nil
  /// for none.
  private static func validate(_ request: VerifySpawnRequest) throws(VerifySpawnError) -> Double? {
    guard let file = request.command.first else {
      throw .commandMissing
    }
    guard !file.isEmpty else {
      throw .commandEmpty
    }
    if file.utf16.contains(0) {
      throw .nullByte(argument: "file", value: file)
    }
    for (index, argument) in request.command.dropFirst().enumerated()
      where argument.utf16.contains(0)
    {
      throw .nullByte(argument: "args[\(index)]", value: argument)
    }
    guard let seconds = request.timeoutSeconds else {
      return nil
    }
    let milliseconds = seconds * 1000
    guard milliseconds.isFinite, milliseconds.rounded(.towardZero) == milliseconds else {
      throw .timeoutNotInteger(milliseconds: milliseconds)
    }
    guard milliseconds >= 0, milliseconds <= largestTimeoutMilliseconds else {
      throw .timeoutOutOfRange(milliseconds: milliseconds)
    }
    return milliseconds > 0 ? milliseconds : nil
  }

  /// `execvp`'s search: a name with a slash as a path, else each `PATH` entry
  /// in turn (`/usr/bin:/bin` when unset, an empty entry meaning `cwd`).
  private static func executable(
    _ name: String,
    workingDirectory: String,
  ) -> String? {
    let anchored = { (path: String) in
      path.hasPrefix("/") ? path : NodePath.join(workingDirectory, path)
    }
    if name.contains("/") {
      let path = anchored(name)
      return isExecutableFile(path) ? path : nil
    }
    let search = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
    return search
      .split(separator: ":", omittingEmptySubsequences: false)
      .map { entry in
        anchored(NodePath.join(entry.isEmpty ? "." : String(entry), name))
      }
      .first(where: isExecutableFile)
  }

  private static func isDirectory(_ path: String) -> Bool {
    var status = stat()
    return stat(path, &status) == 0 && status.st_mode & S_IFMT == S_IFDIR
  }

  private static func isExecutableFile(_ path: String) -> Bool {
    var status = stat()
    guard stat(path, &status) == 0, status.st_mode & S_IFMT == S_IFREG else {
      return false
    }
    return access(path, X_OK) == 0
  }
}

private struct LaunchedChild {
  let process: Process
  let output: Pipe
  let error: Pipe
}

/// The bytes read so far and why reading stopped.
private struct OutputCapture {
  enum Ending {
    case finished
    case timedOut
    case overflowed
  }

  let descriptors: [Int32]
  let deadline: ContinuousClock.Instant?
  var buffers: [[UInt8]] = [[], []]

  /// Read both pipes until both are closed, the deadline passes, or the
  /// combined output exceeds the cap.
  mutating func drain() -> Ending {
    var open = [true, true]
    var chunk = [UInt8](repeating: 0, count: VerifyProcessRunner.readChunkBytes)
    while open.contains(true) {
      guard let wait = remainingMilliseconds() else {
        return .timedOut
      }
      var polled = descriptors.indices.filter { open[$0] }.map { index in
        pollfd(fd: descriptors[index], events: Int16(POLLIN), revents: 0)
      }
      let ready = poll(&polled, nfds_t(polled.count), wait)
      if ready < 0, errno != EINTR {
        return .finished
      }
      guard ready > 0 else {
        continue
      }
      for entry in polled where entry.revents != 0 {
        guard let index = descriptors.firstIndex(of: entry.fd) else {
          continue
        }
        let count = read(entry.fd, &chunk, chunk.count)
        if count > 0 {
          buffers[index] += chunk[0 ..< count]
          if buffers[0].count + buffers[1].count > VerifyProcessRunner.maximumOutputBytes {
            return .overflowed
          }
        } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
          open[index] = false
        }
      }
    }
    return .finished
  }

  /// Wait for the child to be reaped. With both pipes closed but the child
  /// still running, the deadline still applies: past it the child gets
  /// SIGTERM. False when that happened.
  func waitForExit(
    _ process: Process,
    killOnDeadline: Bool,
  ) -> Bool {
    guard killOnDeadline, deadline != nil else {
      process.waitUntilExit()
      return true
    }
    while process.isRunning {
      guard let wait = remainingMilliseconds() else {
        kill(process.processIdentifier, SIGTERM)
        process.waitUntilExit()
        return false
      }
      var none = pollfd()
      _ = poll(&none, 0, min(wait, 5))
    }
    process.waitUntilExit()
    return true
  }

  /// Milliseconds until the deadline, rounded up; -1 (wait forever) with no
  /// deadline; nil once it has passed.
  private func remainingMilliseconds() -> Int32? {
    guard let deadline else {
      return -1
    }
    let remaining = deadline - ContinuousClock.now
    guard remaining > .zero else {
      return nil
    }
    let (seconds, attoseconds) = remaining.components
    guard seconds < Int64(Int32.max / 1000) else {
      return Int32.max
    }
    let milliseconds = seconds * 1000 + (attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
    return Int32(max(1, milliseconds))
  }
}
