import Testing
import UseCasesTestSupport

struct GateTests {
  private let gate = Gate()

  @Test
  func `a waiter goes through only once the gate opens`() async {
    let opened = CancellationSwitch()
    let waiter = Task {
      await gate.wait()

      return await opened.isCancelled()
    }

    await gate.nextWaiter()
    opened.raise()
    await gate.open()

    #expect(await waiter.value)
  }

  @Test
  func `a gate opened before anyone waits stays open`() async {
    await gate.open()

    await gate.wait()
    await gate.wait()
  }

  @Test
  func `every waiter goes through when the gate opens`() async {
    await withTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 3 {
        group.addTask {
          await gate.wait()
        }
      }

      for _ in 0 ..< 3 {
        await gate.nextWaiter()
      }

      await gate.open()
    }
  }

  @Test
  func `opening the gate again changes nothing`() async {
    await gate.open()
    await gate.open()

    await gate.wait()
  }
}
