import Foundation

/// A command step as a real process, behaving as node's
/// `spawnSync(file, args, { cwd, env, encoding: "utf8", shell: false, timeout,
/// maxBuffer: 1 MiB })` does, measured against node 26 on this machine:
///
/// - node's argument checks run first and throw: a NUL in the file, then in
///   an argument, then in the working directory, then a timeout that is not a
///   whole number;
/// - no shell; libuv's `posix_spawn` path: a file holding `/` is spawned as
///   given, anything else is searched for along the CHILD environment's
///   `PATH` (`/usr/bin:/bin` when it has none), where an empty or relative
///   entry is read from the working directory, `EACCES` is remembered while
///   `ENOENT` and `ENOTDIR` move on, and a name over 255 bytes is
///   `ENAMETOOLONG`;
/// - a program that never starts has no status, signal or streams, only
///   `spawnSync <file> <ERRNO>`;
/// - the child has exactly the environment given, default signal dispositions,
///   no blocked signals, and an empty stdin; all three streams are socket
///   pairs, as libuv makes them;
/// - both streams are read until both close. Past the timeout, or once the
///   bytes read across both streams exceed 1 MiB (the read that crosses is
///   kept), the child gets SIGTERM, reading stops, and only its exit is
///   waited for — which a child that ignores SIGTERM can still make with a
///   status of its own;
/// - a signal that ends the child is reported by name, with no status;
/// - each stream is decoded once, at the end, as UTF-8 with each maximal
///   invalid subpart replaced by U+FFFD.
public struct CapsuleProcessSpawner: CapsuleCommandSpawning {
  /// Reads the real process table.
  public init() {}

  public func spawn(_ request: CapsuleSpawnRequest) throws(CapsuleSpawnError)
    -> CapsuleSpawnOutcome
  {
    try Self.validate(request)
    let launch: CapsuleProcessLaunch
    switch CapsuleProcessLaunch.start(request) {
    case let .success(started):
      launch = started
    case let .failure(failure):
      let code = CapsuleSystemNames.errorName(failure.errorNumber)
      return CapsuleSpawnOutcome(
        exitStatus: nil,
        signal: nil,
        standardOutput: nil,
        standardError: nil,
        errorMessage: "spawnSync \(request.executable) \(code)",
      )
    }

    var capture = CapsuleOutputCapture(
      descriptors: [launch.standardOutput, launch.standardError],
      deadline: ContinuousClock.now + .milliseconds(Int64(request.timeoutMilliseconds)),
    )
    let ending = capture.drain()
    // node signals before it closes the streams: a child still writing gets
    // SIGTERM, not the SIGPIPE a closed stream would raise first.
    if ending != .finished {
      kill(launch.processIdentifier, SIGTERM)
    }
    close(launch.standardOutput)
    close(launch.standardError)
    let status = capture.waitForExit(launch.processIdentifier, isKillPending: ending == .finished)
    return CapsuleSpawnOutcome(
      exitStatus: Self.exitCode(status),
      signal: Self.terminatingSignal(status).map(CapsuleSystemNames.signalName),
      standardOutput: UTF8Text.decodeReplacingInvalid(capture.buffers[0]),
      standardError: UTF8Text.decodeReplacingInvalid(capture.buffers[1]),
      errorMessage: nil,
    )
  }

  /// node's refusals, in its order.
  private static func validate(_ request: CapsuleSpawnRequest) throws(CapsuleSpawnError) {
    if request.executable.utf16.contains(0) {
      throw .nullByteInArgument(argument: "file", value: request.executable)
    }
    for (index, argument) in request.arguments.enumerated() where argument.utf16.contains(0) {
      throw .nullByteInArgument(argument: "args[\(index)]", value: argument)
    }
    if request.workingDirectory.utf16.contains(0) {
      throw .nullByteInWorkingDirectory(request.workingDirectory)
    }
    let milliseconds = request.timeoutMilliseconds
    guard milliseconds.isFinite, milliseconds.rounded(.towardZero) == milliseconds else {
      throw .timeoutNotInteger(milliseconds: milliseconds)
    }
  }

  /// `WEXITSTATUS` when the child exited.
  private static func exitCode(_ status: Int32) -> Int? {
    status & 0x7F == 0 ? Int((status >> 8) & 0xFF) : nil
  }

  /// `WTERMSIG` when a signal ended the child.
  private static func terminatingSignal(_ status: Int32) -> Int32? {
    let signal = status & 0x7F
    return signal != 0 && signal != 0x7F ? signal : nil
  }
}
