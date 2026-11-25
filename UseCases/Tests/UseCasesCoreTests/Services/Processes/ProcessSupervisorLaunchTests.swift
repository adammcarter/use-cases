import Foundation
import Testing
@testable import UseCasesCore

struct ProcessSupervisorLaunchTests {
  private let fixture: ProcessFixture

  init() throws {
    fixture = try ProcessFixture()
  }

  private func launchFailure(
    arguments: [String],
    workingDirectory: URL? = nil,
  ) async -> ProcessSupervisingError? {
    let request = ProcessRequest(
      arguments: arguments,
      workingDirectory: workingDirectory ?? fixture.directory.url,
      reportPath: nil,
      timeout: .seconds(10),
    )

    do {
      _ = try await fixture.supervisor().run(request)

      return nil
    } catch {
      return error
    }
  }

  @Test
  func `a command that is not found is a launch error`() async throws {
    let error = try #require(await launchFailure(arguments: ["no-such-program-anywhere"]))

    guard case let .couldNotLaunch(reason) = error else {
      Issue.record("expected a launch error, got \(error)")

      return
    }

    #expect(reason.contains("No such file"))
    #expect(error.description.hasPrefix("command could not be launched: "))
  }

  @Test
  func `a relative path that is not there is a launch error`() async {
    let error = await launchFailure(arguments: ["scripts/missing.sh"])

    #expect(error != nil)
  }

  @Test
  func `a file that is not executable is a launch error`() async throws {
    try fixture.directory.write(
      "tool.sh",
      "#!/bin/sh\necho ran\n",
    )

    let error = await launchFailure(arguments: ["./tool.sh"])

    #expect(error != nil)
  }

  @Test
  func `a working folder that is missing is a launch error that names the folder`() async throws {
    let missing = fixture.directory.location(of: "nowhere")

    let error = try #require(await launchFailure(
      arguments: ["/bin/sh", "-c", "true"],
      workingDirectory: missing,
    ))

    #expect(error.description.contains("working folder \(missing.path)"))
  }

  @Test
  func `a working folder that is a file is a launch error`() async throws {
    try fixture.directory.write("plain-file")

    let error = await launchFailure(
      arguments: ["/bin/sh", "-c", "true"],
      workingDirectory: fixture.directory.location(of: "plain-file"),
    )

    #expect(error != nil)
  }

  @Test
  func `an empty command is a launch error`() async {
    let error = await launchFailure(arguments: [])

    #expect(error == .couldNotLaunch(reason: "the command is empty"))
  }

  @Test
  func `a bare name is found through the PATH of the process`() async throws {
    let run = try await fixture.supervisor().run(
      ProcessRequest(
        arguments: ["sh", "-c", "echo found"],
        workingDirectory: fixture.directory.url,
        reportPath: nil,
        timeout: .seconds(30),
      ),
    )

    #expect(run.console.text == "found\n")
  }

  @Test
  func `a relative path is resolved from the working folder`() async throws {
    // The program is made by a command of its own, so this process never holds it open to write:
    // a command another test starts at that moment would hold a copy of that descriptor until it
    // runs its program, and running this one would then fail as busy.
    try fixture.directory.write(
      "tool.txt",
      "#!/bin/sh\necho ran in $(pwd -P)\n",
    )
    let made = try await fixture.run(
      "mkdir scripts && cp tool.txt scripts/tool.sh && chmod 755 scripts/tool.sh",
    )
    try #require(made.termination == .exited(0))

    let run = try await fixture.supervisor().run(
      ProcessRequest(
        arguments: ["scripts/tool.sh"],
        workingDirectory: fixture.directory.url,
        reportPath: nil,
        timeout: .seconds(30),
      ),
    )

    #expect(run.termination == .exited(0))
    #expect(run.console.text == "ran in \(fixture.directory.url.path)\n")
  }
}
