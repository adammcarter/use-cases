import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

struct RunningCallsTests {
  private let ended = CallTool.Result(content: [], isError: false)

  @Test
  func `a call is run and its answer given back`() async {
    let calls = RunningCalls()
    let answer = ended

    let result = await calls.run {
      .success(answer)
    }

    #expect(result == .success(ended))
  }

  @Test
  func `cancelling everything with nothing running returns at once`() async {
    await RunningCalls().cancelAll()
  }

  @Test
  func `cancelling everything cancels the calls running and waits until they have ended`() async {
    let calls = RunningCalls()
    let runner = MockCommandRunning(.runningUntilCancelled)

    // Two calls at once: neither waits for the other.
    let answers = Task {
      await withTaskGroup(of: RunningCalls.Answer.self) { group in
        for _ in 0 ..< 2 {
          group.addTask {
            await calls.run {
              _ = try? await runner.run(CommandInvocation(
                arguments: ["x"],
                workingDirectory: .temporaryDirectory,
              ))

              return .failure(.cancelled)
            }
          }
        }

        var all: [RunningCalls.Answer] = []
        for await answer in group {
          all.append(answer)
        }

        return all
      }
    }
    var seen = 0
    for await _ in runner.starts {
      seen += 1

      if seen == 2 {
        break
      }
    }

    await calls.cancelAll()

    #expect(await answers.value == [.failure(.cancelled), .failure(.cancelled)])
  }

  @Test
  func `a call cancelled by its caller is cancelled`() async {
    let calls = RunningCalls()
    let runner = MockCommandRunning(.runningUntilCancelled)

    let call = Task {
      await calls.run {
        _ = try? await runner.run(CommandInvocation(
          arguments: ["x"],
          workingDirectory: .temporaryDirectory,
        ))

        return .failure(.cancelled)
      }
    }
    for await _ in runner.starts {
      break
    }
    call.cancel()

    #expect(await call.value == .failure(.cancelled))
  }
}
