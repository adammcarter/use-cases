import Foundation
import UseCasesTestSupport

/// A real folder for the tests of the waiting helpers, and the child shells they start there.
struct WaitingFixture {
  let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  func location(of name: String) -> URL {
    directory.location(of: name)
  }

  /// `script` run by `/bin/sh -c` in the fixture's folder, with nothing to read, holding a pipe
  /// that tells the test when it and everything it started have gone. Its errors go nowhere, so a
  /// child left behind never holds the test run's own output open.
  func start(_ script: String) throws -> ShellChild {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", script]
    process.currentDirectoryURL = directory.url
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice

    let holders = PipeHolders()
    try holders.run(process)

    return ShellChild(
      process: process,
      holders: holders,
    )
  }
}
