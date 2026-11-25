import Foundation

/// Runs the commands of `verify --run` under the process supervisor: directly, in their own
/// process group, with no input, bounded in time and in the output kept (chapter 14).
struct RunCommandExecutor<ClockType: Clock>: RunCommandExecuting
  where ClockType.Duration == Duration
{
  private let supervisor: any ProcessSupervising
  private let writer: Result<any VerifyRunWriting, StoreSchemaLoadingError>
  private let clock: ClockType

  /// - Parameter clock: Times each command.
  init(
    supervisor: any ProcessSupervising,
    writer: Result<any VerifyRunWriting, StoreSchemaLoadingError>,
    clock: ClockType,
  ) {
    self.supervisor = supervisor
    self.writer = writer
    self.clock = clock
  }

  func execute(
    _ validation: BridgeValidation,
    in run: OpenRun,
  ) async throws(VerifyError) -> CommandExecution {
    guard let command = validation.run else {
      return .ran(.missing)
    }

    let writer = try opened()
    let request = ProcessRequest(
      arguments: command,
      workingDirectory: Self.workingFolder(
        of: validation,
        in: run.workspace,
      ),
      reportPath: ReportPaths(validation: validation).absolute(
        of: run.identifier,
        in: run.workspace,
      ),
      timeout: ProcessTimeout.runCommand(timeoutSeconds: validation.timeoutSeconds),
    )
    let began = clock.now
    let ended: ProcessRun

    do {
      ended = try await supervisor.run(request)
    } catch {
      return .ran(
        RanCommand(
          command: command,
          failure: Self.failure(
            of: error,
            launching: command,
          ),
          exitCode: nil,
          seconds: Self.seconds(since: began, on: clock),
        ),
      )
    }

    let seconds = Self.seconds(since: began, on: clock)

    // A request cancelled before the command started never ran it, and has no console to keep.
    if ended.wasLaunched {
      do {
        try writer.writeConsole(
          ended.console.text,
          of: validation.identifier,
          in: run,
        )
      } catch {
        throw .storage(error.description)
      }
    }

    return Self.execution(
      of: command,
      ending: ended.termination,
      seconds: seconds,
    )
  }

  private func opened() throws(VerifyError) -> any VerifyRunWriting {
    switch writer {
    case let .success(writer):
      return writer
    case let .failure(error):
      throw .storage("the store's schemas could not be loaded: \(error)")
    }
  }

  /// The validation's `working_dir`, or the workspace root when it has none (chapter 14 §8).
  private static func workingFolder(
    of validation: BridgeValidation,
    in root: URL,
  ) -> URL {
    guard let path = validation.workingDirectory, !path.isRoot else {
      return root
    }

    return URL(
      fileURLWithPath: "\(root.path)/\(path.text)",
      isDirectory: true,
    )
  }

  private static func execution(
    of command: [String],
    ending termination: ProcessTermination,
    seconds: Double,
  ) -> CommandExecution {
    if case .cancelled = termination {
      return .cancelled
    }

    var exitCode: Int32?

    if case let .exited(code) = termination {
      exitCode = code
    }

    return .ran(
      RanCommand(
        command: command,
        failure: termination.runErrorWords,
        exitCode: exitCode,
        seconds: seconds,
      ),
    )
  }

  private static func seconds(
    since start: ClockType.Instant,
    on clock: ClockType,
  ) -> Double {
    let elapsed = start.duration(to: clock.now).components

    let seconds = Double(elapsed.seconds) + Double(elapsed.attoseconds) / 1e18

    return (seconds * 1000).rounded() / 1000
  }

  /// A command that could not be launched says which program it was, since the reason alone
  /// ("No such file or directory") does not.
  private static func failure(
    of error: ProcessSupervisingError,
    launching command: [String],
  ) -> String {
    guard case let .couldNotLaunch(reason) = error, let program = command.first else {
      return error.description
    }

    return "command could not be launched: \(program): \(reason)"
  }
}

extension RunCommandExecutor where ClockType == ContinuousClock {
  /// An executor that times each command on the system's monotonic clock, as production does
  /// (chapter 14 §11).
  init(
    supervisor: any ProcessSupervising,
    writer: Result<any VerifyRunWriting, StoreSchemaLoadingError>,
  ) {
    self.init(
      supervisor: supervisor,
      writer: writer,
      clock: ContinuousClock(),
    )
  }
}
