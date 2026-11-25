import Testing
import UseCasesCore
import UseCasesTestSupport

struct CancellationSwitchTests {
  @Test
  func `a new switch is not raised`() async {
    let cancellation: any CancellationObserving = CancellationSwitch()

    #expect(await cancellation.isCancelled() == false)
  }

  @Test
  func `a raise from a synchronous hook is seen by every later look`() async {
    let cancellation = CancellationSwitch()
    let hook: @Sendable () -> Void = {
      cancellation.raise()
    }

    hook()

    #expect(await cancellation.isCancelled())
    #expect(await cancellation.isCancelled())
  }

  @Test
  func `raises from many tasks at once leave the switch raised`() async {
    let cancellation = CancellationSwitch()

    await withTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 100 {
        group.addTask {
          cancellation.raise()
        }
      }
    }

    #expect(await cancellation.isCancelled())
  }
}
