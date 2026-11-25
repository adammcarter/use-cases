import MCP

/// The tool calls running now, so that a server that is being stopped can cancel them all, which
/// stops their commands, and wait until they have ended. Calls do not wait for one another.
///
/// Once everything has been cancelled the calls are closed: a call that arrives after that, which
/// the host sent just before it closed its input, is answered cancelled without starting
/// anything, so no command outlives the server.
actor RunningCalls {
  typealias Answer = Result<CallTool.Result, ToolCallError>

  private var tasks: [Int: Task<Answer, Never>] = [:]
  private var waiting: [CheckedContinuation<Void, Never>] = []
  private var nextKey = 0
  private var isClosed = false

  /// Runs `work` as a task of its own that cancelling the caller, or ``cancelAll()``, cancels.
  /// Once ``cancelAll()`` has been called nothing is started: the answer is cancelled.
  func run(_ work: @escaping @Sendable () async -> Answer) async -> Answer {
    guard !isClosed else {
      return .failure(.cancelled)
    }

    let task = Task {
      await work()
    }

    let key = nextKey
    nextKey += 1
    tasks[key] = task

    let answer = await withTaskCancellationHandler {
      await task.value
    } onCancel: {
      task.cancel()
    }

    finish(key)

    return answer
  }

  /// Cancels every call running now, closes the calls to any that would start later, and returns
  /// once those running have all ended.
  func cancelAll() async {
    isClosed = true

    for task in tasks.values {
      task.cancel()
    }

    while !tasks.isEmpty {
      await withCheckedContinuation { continuation in
        waiting.append(continuation)
      }
    }
  }

  private func finish(_ key: Int) {
    tasks[key] = nil

    guard tasks.isEmpty else {
      return
    }

    let ended = waiting
    waiting = []

    for continuation in ended {
      continuation.resume()
    }
  }
}
