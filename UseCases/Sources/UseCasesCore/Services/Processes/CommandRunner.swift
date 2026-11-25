import Foundation

/// Runs programs as chapter 14 runs a command, with stdout and stderr in separate files read
/// whole, an optional stdin from a file, and no time limit. Only cancelling the task stops one.
public struct CommandRunner: CommandRunning {
  private let launcher = ProcessLauncher()
  private let watcher: any ProcessWatching

  /// - Parameters:
  ///   - terminationGrace: How long a program's group gets to end after SIGTERM before SIGKILL.
  ///   - pollInterval: How often a running program is looked at.
  public init(
    terminationGrace: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
  ) {
    self.init(
      terminationGrace: terminationGrace,
      pollInterval: pollInterval,
      cancellation: NeverCancelled(),
      clock: ContinuousClock(),
    )
  }

  /// A runner that also stops a program when `cancellation` says so, which a test can decide
  /// without cancelling a task, and paces its looks and times the grace on `clock`.
  init<ClockType: Clock>(
    terminationGrace: Duration,
    pollInterval: Duration,
    cancellation: any CancellationObserving,
    clock: ClockType,
  ) where ClockType.Duration == Duration {
    let reaper = ProcessReaper()

    self.init(
      watcher: ProcessWatcher(
        cancellation: cancellation,
        clock: clock,
        pollInterval: pollInterval,
        reaper: reaper,
        stopper: ProcessGroupStopper(
          clock: clock,
          grace: terminationGrace,
          pollInterval: pollInterval,
          reaper: reaper,
        ),
      ),
    )
  }

  /// A runner that watches its programs with `watcher`.
  init(watcher: any ProcessWatching) {
    self.watcher = watcher
  }

  public func run(
    _ invocation: CommandInvocation,
  ) async throws(CommandRunningError) -> CommandOutcome {
    do throws(ProcessSupervisingError) {
      return try await outcome(of: invocation)
    } catch {
      throw .couldNotRun(reason: error.description)
    }
  }

  private func outcome(
    of invocation: CommandInvocation,
  ) async throws(ProcessSupervisingError) -> CommandOutcome {
    guard !Task.isCancelled else {
      return CommandOutcome(
        ending: .cancelled,
        standardOutput: "",
        standardError: "",
      )
    }

    let input = try input(for: invocation)
    defer {
      input?.release()
    }

    let output = try ConsoleCaptureFile.create()
    defer {
      output.release()
    }

    let error = try ConsoleCaptureFile.create()
    defer {
      error.release()
    }

    let leader = try launcher.launch(
      arguments: invocation.arguments,
      workingDirectory: invocation.workingDirectory,
      streams: ProcessStreams(
        input: input?.descriptor,
        output: output.descriptor,
        error: error.descriptor,
        lifeline: invocation.lifeline,
      ),
    )

    let termination = try await watcher.watch(
      leader: leader,
      timeout: nil,
    )

    return try CommandOutcome(
      ending: ending(of: termination),
      standardOutput: output.readEverything(),
      standardError: error.readEverything(),
    )
  }

  /// The text the program reads, put in a file of its own.
  private func input(
    for invocation: CommandInvocation,
  ) throws(ProcessSupervisingError) -> ConsoleCaptureFile? {
    guard let text = invocation.standardInput else {
      return nil
    }

    let file = try ConsoleCaptureFile.create()

    do throws(ProcessSupervisingError) {
      try file.fill(with: text)
    } catch {
      file.release()

      throw error
    }

    return file
  }

  private func ending(of termination: ProcessTermination) -> CommandEnding {
    switch termination {
    case let .exited(code):
      .exited(code)
    case let .signaled(signal):
      .signaled(signal)
    case .cancelled, .timedOut:
      // Nothing here gives a program a time limit; a stop is always a cancellation.
      .cancelled
    }
  }
}
