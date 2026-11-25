import MCP
import Testing
@testable import UseCasesMCP

struct RunningCallsClosingTests {
  /// Counts the work it is asked to do.
  private actor Starts {
    private(set) var times = 0

    func started() {
      times += 1
    }
  }

  @Test
  func `a call that arrives after everything was cancelled is cancelled and starts nothing`(
  ) async {
    let calls = RunningCalls()
    let starts = Starts()

    await calls.cancelAll()
    let answer = await calls.run {
      await starts.started()

      return .success(CallTool.Result(content: [], isError: false))
    }

    #expect(answer == .failure(.cancelled))
    #expect(await starts.times == 0)
  }

  @Test
  func `calls that arrive after everything was cancelled never start, however many`() async {
    let calls = RunningCalls()
    let starts = Starts()

    await calls.cancelAll()
    await withTaskGroup(of: Void.self) { group in
      for _ in 0 ..< 20 {
        group.addTask {
          _ = await calls.run {
            await starts.started()

            return .failure(.cancelled)
          }
        }
      }
    }

    #expect(await starts.times == 0)
  }

  @Test
  func `a call before the cancelling is run, and the one after it is not`() async {
    let calls = RunningCalls()
    let starts = Starts()

    let first = await calls.run {
      await starts.started()

      return .success(CallTool.Result(content: [], isError: false))
    }
    await calls.cancelAll()
    let second = await calls.run {
      await starts.started()

      return .success(CallTool.Result(content: [], isError: false))
    }

    #expect(first == .success(CallTool.Result(content: [], isError: false)))
    #expect(second == .failure(.cancelled))
    #expect(await starts.times == 1)
  }
}
