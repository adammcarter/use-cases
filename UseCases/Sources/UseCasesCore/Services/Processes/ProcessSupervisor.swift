import Foundation

/// Runs commands for `verify --run` and for the transformers (chapter 14, chapter 10 §10).
///
/// Waiting is a polling loop on the injected clock, so nothing blocks a thread of the
/// concurrency pool and a test can use a clock and durations of its own.
struct ProcessSupervisor<ClockType: Clock>: ProcessSupervising
  where ClockType.Duration == Duration
{
  private let launcher: any ProcessLaunching
  private let watcher: any ProcessWatching
  private let makeCapture: @Sendable () throws(ProcessSupervisingError) -> any ConsoleCapturing

  /// - Parameters:
  ///   - cancellation: Says whether the run was cancelled.
  ///   - clock: Times the commands.
  ///   - pollInterval: How often a running command is looked at.
  ///   - launcher: Starts a command.
  ///   - reaper: Asks whether a command has ended.
  ///   - stopper: Stops a command's whole group.
  ///   - makeCapture: Makes the capture a command's output goes to.
  init(
    cancellation: any CancellationObserving,
    clock: ClockType,
    pollInterval: Duration,
    launcher: any ProcessLaunching,
    reaper: any ProcessReaping,
    stopper: any ProcessGroupStopping,
    makeCapture: @escaping @Sendable () throws(ProcessSupervisingError) -> any ConsoleCapturing,
  ) {
    self.init(
      launcher: launcher,
      watcher: ProcessWatcher(
        cancellation: cancellation,
        clock: clock,
        pollInterval: pollInterval,
        reaper: reaper,
        stopper: stopper,
      ),
      makeCapture: makeCapture,
    )
  }

  /// - Parameters:
  ///   - launcher: Starts a command.
  ///   - watcher: Watches a started command until it ends, its time is up, or the run is
  ///     cancelled.
  ///   - makeCapture: Makes the capture a command's output goes to.
  init(
    launcher: any ProcessLaunching,
    watcher: any ProcessWatching,
    makeCapture: @escaping @Sendable () throws(ProcessSupervisingError) -> any ConsoleCapturing,
  ) {
    self.launcher = launcher
    self.watcher = watcher
    self.makeCapture = makeCapture
  }

  /// A supervisor as production builds it: `posix_spawn`, `waitpid`, `killpg` and a scratch file.
  ///
  /// - Parameters:
  ///   - cancellation: Says whether the run was cancelled.
  ///   - clock: Times the commands.
  ///   - terminationGrace: How long a group gets to end after SIGTERM before SIGKILL (2 s).
  ///   - pollInterval: How often a running command is looked at.
  init(
    cancellation: any CancellationObserving,
    clock: ClockType,
    terminationGrace: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
  ) {
    self.init(
      cancellation: cancellation,
      clock: clock,
      pollInterval: pollInterval,
      launcher: ProcessLauncher(),
      reaper: ProcessReaper(),
      stopper: ProcessGroupStopper(
        clock: clock,
        grace: terminationGrace,
        pollInterval: pollInterval,
        reaper: ProcessReaper(),
      ),
      makeCapture: { () throws(ProcessSupervisingError) -> any ConsoleCapturing in
        try ConsoleCaptureFile.create()
      },
    )
  }

  func run(_ request: ProcessRequest) async throws(ProcessSupervisingError) -> ProcessRun {
    // A cancellation that has already arrived starts nothing.
    guard await !watcher.isCancelled() else {
      return ProcessRun(
        termination: .cancelled,
        console: .empty,
        wasLaunched: false,
      )
    }

    let capture = try makeCapture()
    defer {
      capture.release()
    }

    let leader = try launcher.launch(
      arguments: request.launchArguments,
      workingDirectory: request.workingDirectory,
      capture: capture,
    )

    let termination = try await watcher.watch(
      leader: leader,
      timeout: request.timeout,
    )

    return try ProcessRun(
      termination: termination,
      console: capture.read(),
      wasLaunched: true,
    )
  }
}

extension ProcessSupervisor where ClockType == ContinuousClock {
  /// A supervisor on the system's monotonic clock, as production uses.
  init(cancellation: any CancellationObserving) {
    self.init(
      cancellation: cancellation,
      clock: ContinuousClock(),
    )
  }
}
