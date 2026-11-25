import Foundation
import Testing
import UseCasesTestSupport

struct PipeHoldersTests {
  private let fixture: WaitingFixture

  init() throws {
    fixture = try WaitingFixture()
  }

  @Test
  func `every holder has gone once the only child ends`() async throws {
    let child = try fixture.start("exit 0")

    await child.allGone()
  }

  @Test
  func `a process the child started keeps the pipe until it ends`() async throws {
    let hold = try ChildHold(at: fixture.location(of: "hold.fifo"))
    let released = CancellationSwitch()
    let child = try fixture.start("( \(hold.shellText()) ) & exit 0")
    let holders = child.holders
    let watcher = Task {
      await holders.allGone()

      return await released.isCancelled()
    }

    _ = await hold.waitUntilHeld()
    released.raise()
    hold.release()

    #expect(await watcher.value)
  }

  @Test
  func `a cancelled wait is never told the holders have gone while one is still there`(
  ) async throws {
    let hold = try ChildHold(at: fixture.location(of: "hold.fifo"))
    let released = CancellationSwitch()
    let asking = Gate()
    let holders = PipeHolders()
    let cancelledWait = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }
      await asking.open()
      await holders.allGone()

      return await released.isCancelled()
    }

    await asking.wait()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", hold.shellText()]
    process.currentDirectoryURL = fixture.directory.url
    process.standardInput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try holders.run(process)
    _ = await hold.waitUntilHeld()

    let laterWait = Task {
      await holders.allGone()

      return await released.isCancelled()
    }

    released.raise()
    hold.release()

    #expect(await cancelledWait.value)
    #expect(await laterWait.value)
  }

  @Test
  func `what the holders write is drained, so no holder waits to write`() async throws {
    let said = try ChildSignal(at: fixture.location(of: "said.fifo"))
    let child = try fixture.start(
      "head -c 1048576 /dev/zero; \(said.shellText(saying: "written"))",
    )

    #expect(try await said.next() == "written")
    await child.allGone()
  }

  @Test
  func `a child that cannot start leaves no holder`() async {
    let holders = PipeHolders()
    let process = Process()
    process.executableURL = fixture.location(of: "missing")

    #expect(throws: (any Error).self) {
      try holders.run(process)
    }
    await holders.allGone()
  }
}
