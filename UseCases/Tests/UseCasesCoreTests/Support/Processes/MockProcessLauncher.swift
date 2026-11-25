import Foundation
import UseCasesTestSupport
@testable import UseCasesCore

/// A launcher that starts nothing: it answers with a process ID, or refuses. One that is asked
/// when it should not be shows as a refusal.
struct MockProcessLauncher: ProcessLaunching {
  /// Answers every launch with this process ID, after raising `cancellation` if there is one, so
  /// the run is cancelled once the command is going.
  static func starting(
    _ processIdentifier: pid_t,
    raising cancellation: CancellationSwitch? = nil,
  ) -> MockProcessLauncher {
    MockProcessLauncher(
      processIdentifier: processIdentifier,
      cancellation: cancellation,
    )
  }

  /// Refuses every launch, as a test that expects no launch wants to see.
  static let refusing = MockProcessLauncher(
    processIdentifier: nil,
    cancellation: nil,
  )

  let processIdentifier: pid_t?
  let cancellation: CancellationSwitch?

  func launch(
    arguments: [String],
    workingDirectory: URL,
    capture: any ConsoleCapturing,
  ) throws(ProcessSupervisingError) -> pid_t {
    guard let processIdentifier else {
      throw .couldNotLaunch(reason: "a launch that was not expected")
    }

    cancellation?.raise()

    return processIdentifier
  }
}
