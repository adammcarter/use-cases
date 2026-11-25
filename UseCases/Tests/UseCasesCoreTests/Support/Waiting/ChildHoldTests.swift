import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

struct ChildHoldTests {
  /// The shells a held script is tried under: the system's `sh`, and dash wherever it is
  /// installed, which ends a read on a trapped signal just as at the end of the file.
  static let shells = ["/bin/sh", "/bin/dash"].filter { path in
    FileManager.default.isExecutableFile(atPath: path)
  }

  private let fixture: WaitingFixture

  init() throws {
    fixture = try WaitingFixture()
  }

  private func hold() throws -> ChildHold {
    try ChildHold(at: fixture.location(of: "hold.fifo"))
  }

  @Test
  func `a held child goes on only once the hold is released`() async throws {
    let hold = try hold()
    let said = try ChildSignal(at: fixture.location(of: "said.fifo"))
    // The child looks for a file the test writes only after the child is held: a child that
    // went on early would find nothing there.
    let child = try fixture.start(
      """
      \(hold.shellText()); if [ -e released ]; then \(said.shellText(saying: "released")); \
      else \(said.shellText(saying: "early")); fi
      """,
    )

    _ = await hold.waitUntilHeld()
    try "released".write(
      to: fixture.location(of: "released"),
      atomically: true,
      encoding: .utf8,
    )
    hold.release()

    #expect(try await said.next() == "released")
    await child.allGone()
  }

  @Test
  func `a held child that traps TERM is still held after TERM, and goes on once released`(
  ) async throws {
    let hold = try hold()
    let said = try ChildSignal(at: fixture.location(of: "said.fifo"))
    let holders = PipeHolders()
    // Started as the product starts a command: in a group of its own, every signal at its
    // default and none blocked, so TERM to the group reaches both the shell and its read.
    let script = """
    trap "\(said.shellText(saying: "got-term"))" TERM; \(hold.shellText()); \
    if [ -e released ]; then \(said.shellText(saying: "released")); \
    else \(said.shellText(saying: "early")); fi
    """
    let leader = try holders.handWriteEnd { descriptor in
      try ProcessLauncher().launch(
        arguments: ["/bin/sh", "-c", script],
        workingDirectory: fixture.directory.url,
        streams: ProcessStreams(
          input: nil,
          output: descriptor,
          error: descriptor,
        ),
      )
    }

    _ = await hold.waitUntilHeld()
    killpg(leader, SIGTERM)
    #expect(try await said.next() == "got-term")

    try "released".write(
      to: fixture.location(of: "released"),
      atomically: true,
      encoding: .utf8,
    )
    hold.release()

    #expect(try await said.next() == "released")
    await holders.allGone()
  }

  @Test(arguments: shells)
  func `a held child that traps TERM twice is still held after both, and goes on once released`(
    shell: String,
  ) async throws {
    let hold = try hold()
    let said = try ChildSignal(at: fixture.location(of: "said.fifo"))
    let holders = PipeHolders()
    // The first TERM stops the child reading the hold; the second reaches the shell's own read.
    // A shell puts off the trap for a TERM that comes just before that read begins, until the
    // read returns: the nudge makes it return without letting the child go.
    let script = """
    trap "\(said.shellText(saying: "got-term"))" TERM; \(hold.shellText()); \
    if [ -e released ]; then \(said.shellText(saying: "released")); \
    else \(said.shellText(saying: "early")); fi
    """
    let leader = try holders.handWriteEnd { descriptor in
      try ProcessLauncher().launch(
        arguments: [shell, "-c", script],
        workingDirectory: fixture.directory.url,
        streams: ProcessStreams(
          input: nil,
          output: descriptor,
          error: descriptor,
        ),
      )
    }

    _ = await hold.waitUntilHeld()
    killpg(leader, SIGTERM)
    #expect(try await said.next() == "got-term")
    killpg(leader, SIGTERM)
    hold.nudge()
    #expect(try await said.next() == "got-term")

    try "released".write(
      to: fixture.location(of: "released"),
      atomically: true,
      encoding: .utf8,
    )
    hold.release()

    #expect(try await said.next() == "released")
    await holders.allGone()
  }

  @Test
  func `a child that reaches a hold already freed ends rather than waiting for ever`(
  ) async throws {
    let script = try shellTextOfFreedHold()

    let child = try fixture.start(script)

    await child.allGone()
  }

  /// The shell text of a hold that is gone by the time this returns.
  private func shellTextOfFreedHold() throws -> String {
    try hold().shellText()
  }

  @Test
  func `waiting until held gives what the child announced`() async throws {
    let hold = try hold()
    let child = try fixture.start(hold.shellText())

    #expect(await hold.waitUntilHeld() == String(child.process.processIdentifier))

    hold.release()
    await child.allGone()
  }

  @Test
  func `a hold released before the child reaches it lets the child go on`() async throws {
    let hold = try hold()

    hold.release()

    let child = try fixture.start(hold.shellText(announcing: "arrived"))

    #expect(await hold.waitUntilHeld() == "arrived")
    await child.allGone()
  }

  @Test
  func `giving up the wait ends it with nothing when no child comes`() async throws {
    let hold = try hold()
    let waiting = Task {
      await hold.waitUntilHeld()
    }

    hold.giveUp()

    #expect(await waiting.value == nil)
    #expect(await hold.waitUntilHeld() == nil)
  }

  @Test
  func `giving up after the child announced keeps what it announced`() async throws {
    let hold = try hold()
    let child = try fixture.start(hold.shellText(announcing: "arrived"))

    #expect(await hold.waitUntilHeld() == "arrived")
    hold.giveUp()

    #expect(await hold.waitUntilHeld() == "arrived")
    hold.release()
    await child.allGone()
  }

  @Test
  func `releasing the hold again changes nothing`() async throws {
    let hold = try hold()
    let child = try fixture.start(hold.shellText())

    _ = await hold.waitUntilHeld()
    hold.release()
    hold.release()

    await child.allGone()
  }
}
