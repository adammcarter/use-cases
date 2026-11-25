import Foundation
import UseCasesTestSupport
@testable import UseCasesCore

/// Starts a command as production does, its output to the capture, and hands it the write end of
/// `holders` as its lifeline, which it and everything it starts keep: so the test hears from
/// `holders` when they have all gone. One command per launcher.
struct HoldersHandingLauncher: ProcessLaunching {
  let holders: PipeHolders

  func launch(
    arguments: [String],
    workingDirectory: URL,
    capture: any ConsoleCapturing,
  ) throws(ProcessSupervisingError) -> pid_t {
    let launched = holders.handWriteEnd { descriptor in
      Result { () throws(ProcessSupervisingError) -> pid_t in
        try ProcessLauncher().launch(
          arguments: arguments,
          workingDirectory: workingDirectory,
          streams: ProcessStreams(
            input: nil,
            output: capture.descriptor,
            error: capture.descriptor,
            lifeline: descriptor,
          ),
        )
      }
    }

    return try launched.get()
  }
}
