import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A real folder to run real commands in, with the helpers the process tests share.
struct ProcessFixture {
  let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  /// The grace a stop is given, which no test reaches: a group is waited for until it is gone,
  /// which is an event, and never until a stopwatch says so. A test that is about the grace gives
  /// a clock its own, or a grace of its own.
  static let terminationGrace = Duration.seconds(600)

  /// A time limit no test reaches on the system's clock, for a command the test holds: its time
  /// is up only when the test jumps a clock past it, and never because a slow machine took that
  /// long.
  static let timeLimitNoTestReaches = Duration.seconds(31_536_000)

  /// A supervisor on the system clock. A test that needs another clock builds the supervisor
  /// itself.
  func supervisor(
    cancellation: any CancellationObserving = MockCancellation.never,
    terminationGrace: Duration = Self.terminationGrace,
  ) -> ProcessSupervisor<ContinuousClock> {
    ProcessSupervisor(
      cancellation: cancellation,
      clock: ContinuousClock(),
      terminationGrace: terminationGrace,
    )
  }

  /// A supervisor on the system clock whose launcher, reaper and stopper are doubles, so nothing
  /// is started and the test sees what the supervisor asks of them.
  func supervisor(
    cancellation: any CancellationObserving = MockCancellation.never,
    launcher: any ProcessLaunching,
    reaper: any ProcessReaping,
    stopper: any ProcessGroupStopping,
  ) -> ProcessSupervisor<ContinuousClock> {
    ProcessSupervisor(
      cancellation: cancellation,
      clock: ContinuousClock(),
      pollInterval: .milliseconds(1),
      launcher: launcher,
      reaper: reaper,
      stopper: stopper,
      makeCapture: { () throws(ProcessSupervisingError) -> any ConsoleCapturing in
        MockConsoleCapture()
      },
    )
  }

  /// A supervisor on `clock` whose launcher, reaper and stopper are doubles, and whose capture
  /// holds `console`, so nothing is started and the test sees what the supervisor asks of them.
  func supervisor<ClockType: Clock>(
    clock: ClockType,
    cancellation: any CancellationObserving = MockCancellation.never,
    launcher: any ProcessLaunching,
    reaper: any ProcessReaping,
    stopper: any ProcessGroupStopping,
    console: ProcessConsole = .empty,
  ) -> ProcessSupervisor<ClockType> where ClockType.Duration == Duration {
    ProcessSupervisor(
      cancellation: cancellation,
      clock: clock,
      pollInterval: .milliseconds(1),
      launcher: launcher,
      reaper: reaper,
      stopper: stopper,
      makeCapture: { () throws(ProcessSupervisingError) -> any ConsoleCapturing in
        ScriptedConsoleCapture(console: console)
      },
    )
  }

  /// A supervisor of the production parts on `clock`, whose launcher also hands each command
  /// the write end of `holders`, so the test hears when the command and everything it started
  /// have gone. The reapers given are the ones the watcher and the stopper ask.
  func supervisor<ClockType: Clock>(
    clock: ClockType,
    cancellation: any CancellationObserving = MockCancellation.never,
    holders: PipeHolders,
    watcherReaper: any ProcessReaping = ProcessReaper(),
    stopperReaper: any ProcessReaping = ProcessReaper(),
  ) -> ProcessSupervisor<ClockType> where ClockType.Duration == Duration {
    ProcessSupervisor(
      cancellation: cancellation,
      clock: clock,
      pollInterval: .milliseconds(10),
      launcher: HoldersHandingLauncher(holders: holders),
      reaper: watcherReaper,
      stopper: ProcessGroupStopper(
        clock: clock,
        grace: Self.terminationGrace,
        pollInterval: .milliseconds(10),
        reaper: stopperReaper,
      ),
      makeCapture: { () throws(ProcessSupervisingError) -> any ConsoleCapturing in
        try ConsoleCaptureFile.create()
      },
    )
  }

  /// A hold in the fixture's folder, for one child to wait on until the test lets it go.
  func hold(_ name: String = "hold.fifo") throws -> ChildHold {
    try ChildHold(at: directory.location(of: name))
  }

  /// A signal in the fixture's folder, which a child writes lines to.
  func signal(_ name: String) throws -> ChildSignal {
    try ChildSignal(at: directory.location(of: name))
  }

  /// Writes `text` to a script called `name` in the fixture's folder, and gives the shell words
  /// that run it in a shell of its own, whose `$$` is its own process ID.
  func script(
    _ name: String,
    _ text: String,
  ) throws -> String {
    try directory.write(
      name,
      text,
    )

    return "/bin/sh \(name)"
  }

  /// The process ID the child held by `hold` announced, once it is held.
  static func processIdentifier(heldBy hold: ChildHold) async throws -> pid_t {
    let announced = await hold.waitUntilHeld()

    return try #require(
      announced.flatMap { text in
        pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
      },
    )
  }

  /// As `processIdentifier(heldBy:)`, but a failure saying `failure`, rather than a wait for ever,
  /// when `ended` returns before the child is held; the wait for the hold is then given up, so
  /// it is not left suspended either.
  static func processIdentifier(
    heldBy hold: ChildHold,
    unless ended: @escaping @Sendable () async -> Void,
    failing failure: Comment,
  ) async throws -> pid_t {
    let isHeldFirst = await EventRace.isFirst(
      {
        _ = await hold.waitUntilHeld()
      },
      before: ended,
    )

    if !isHeldFirst {
      hold.giveUp()
    }

    try #require(isHeldFirst, failure)

    return try await processIdentifier(heldBy: hold)
  }

  /// As `processIdentifier(heldBy:)`, but a failure rather than a wait for ever when the run
  /// ends before the child is held.
  static func processIdentifier<Success: Sendable>(
    heldBy hold: ChildHold,
    unlessEnded running: Task<Success, any Error>,
  ) async throws -> pid_t {
    try await processIdentifier(
      heldBy: hold,
      unless: {
        _ = await running.result
      },
      failing: "the run ended before the child was held",
    )
  }

  /// `script` run by `/bin/sh -c`, in the fixture's folder.
  func request(
    _ script: String,
    timeout: Duration = .seconds(60),
    reportPath: String? = nil,
  ) -> ProcessRequest {
    ProcessRequest(
      arguments: ["/bin/sh", "-c", script],
      workingDirectory: directory.url,
      reportPath: reportPath,
      timeout: timeout,
    )
  }

  func run(
    _ script: String,
    timeout: Duration = .seconds(60),
    reportPath: String? = nil,
  ) async throws(ProcessSupervisingError) -> ProcessRun {
    try await supervisor().run(
      request(
        script,
        timeout: timeout,
        reportPath: reportPath,
      ),
    )
  }

  /// The shell lines that write `$$` or the given text into `name` in one step, so a test that
  /// sees the file sees all of it.
  static func announce(
    _ name: String,
    _ value: String = "$$",
  ) -> String {
    "echo \(value) > \(name).tmp && mv \(name).tmp \(name)"
  }

  func processIdentifier(announcedIn name: String) throws -> pid_t {
    let text = try String(contentsOf: directory.location(of: name), encoding: .utf8)

    return try #require(pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)))
  }

  /// Whether the process announced in `file` has ended and been collected. `false` while nothing
  /// is announced there yet.
  static func hasEnded(announcedIn file: URL) -> Bool {
    guard
      let text = try? String(contentsOf: file, encoding: .utf8),
      let processIdentifier = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines))
    else {
      return false
    }

    return !exists(processIdentifier)
  }

  /// Whether a process of that ID still exists. One that has ended but not been collected
  /// counts, as it does for the system.
  static func exists(_ processIdentifier: pid_t) -> Bool {
    kill(processIdentifier, 0) == 0
  }
}
