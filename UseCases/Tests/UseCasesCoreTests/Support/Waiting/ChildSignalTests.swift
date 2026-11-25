import Foundation
import Testing
@testable import UseCasesTestSupport

struct ChildSignalTests {
  private let fixture: WaitingFixture

  init() throws {
    fixture = try WaitingFixture()
  }

  private func signal() throws -> ChildSignal {
    try ChildSignal(at: fixture.location(of: "said.fifo"))
  }

  @Test
  func `a line a child writes arrives without its newline`() async throws {
    let signal = try signal()
    let child = try fixture.start(signal.shellText(saying: "hello"))

    #expect(try await signal.next() == "hello")
    await child.allGone()
  }

  @Test
  func `many lines arrive whole and in the order written`() async throws {
    let signal = try signal()
    let child = try fixture.start(
      "i=1; while [ $i -le 500 ]; do \(signal.shellText(saying: "line-$i")); i=$((i + 1)); done",
    )
    var received: [String] = []

    while received.count < 500, let line = try await signal.next() {
      received.append(line)
    }

    let written = (1 ... 500).map { number in
      "line-\(number)"
    }

    #expect(received == written)
    await child.allGone()
  }

  @Test
  func `a line longer than one read arrives whole`() async throws {
    let signal = try signal()
    let length = ChildSignal.readSize * 2 + 100
    let child = try fixture.start(
      signal.shellText(saying: "$(head -c \(length) /dev/zero | tr '\\0' x)"),
    )

    #expect(try await signal.next() == String(repeating: "x", count: length))
    await child.allGone()
  }

  @Test
  func `a signal whose path has a space and an apostrophe still reaches the test`(
  ) async throws {
    let signal = try ChildSignal(at: fixture.location(of: "it's said.fifo"))
    let child = try fixture.start(signal.shellText(saying: "hello"))

    #expect(try await signal.next() == "hello")
    await child.allGone()
  }

  @Test
  func `lines written before anyone listens are kept`() async throws {
    let signal = try signal()
    let child = try fixture.start(
      "\(signal.shellText(saying: "first")); \(signal.shellText(saying: "second"))",
    )

    await child.allGone()

    #expect(try await signal.next() == "first")
    #expect(try await signal.next() == "second")
  }

  @Test
  func `lines from several children all arrive`() async throws {
    let signal = try signal()
    let children = try ["one", "two", "three"].map { word in
      try fixture.start(signal.shellText(saying: word))
    }
    var received: Set<String> = []

    while received.count < 3, let line = try await signal.next() {
      received.insert(line)
    }

    #expect(received == ["one", "two", "three"])

    for child in children {
      await child.allGone()
    }
  }

  @Test
  func `closing the signal ends its lines`() async throws {
    let signal = try signal()

    signal.close()

    #expect(try await signal.next() == nil)
  }

  @Test
  func `a child that writes after the signal is closed makes a plain file, not a pipe it waits on`(
  ) async throws {
    let signal = try signal()

    signal.close()

    let child = try fixture.start(signal.shellText(saying: "late"))
    await child.allGone()

    let written = try String(
      contentsOf: signal.url,
      encoding: .utf8,
    )
    #expect(written == "late\n")
  }

  @Test
  func `a cancelled wait throws and leaves the next line for the next wait`() async throws {
    let signal = try signal()
    let cancelled = Task {
      withUnsafeCurrentTask { task in
        task?.cancel()
      }

      return try await signal.next()
    }

    await #expect(throws: CancellationError.self) {
      try await cancelled.value
    }

    let child = try fixture.start(signal.shellText(saying: "hello"))

    #expect(try await signal.next() == "hello")
    await child.allGone()
  }

  @Test
  func `a wait cancelled while waiting throws and leaves the next line for the next wait`(
  ) async throws {
    let lines = ChildSignalLines()
    let waiting = Task {
      try await lines.next(cancellation: CancellationFlag())
    }

    await lines.nextWaiter()
    waiting.cancel()

    await #expect(throws: CancellationError.self) {
      try await waiting.value
    }

    await lines.receive(["hello"])
    #expect(try await lines.next(cancellation: CancellationFlag()) == "hello")
  }

  @Test
  func `a wait cancelled before its cancel reaches the lines throws, and the line goes on`(
  ) async throws {
    let lines = ChildSignalLines()
    let cancellation = CancellationFlag()
    let waiting = Task {
      try await lines.wait(
        ticket: 0,
        cancellation: cancellation,
      )
    }

    await lines.nextWaiter()
    // Raised as a cancel raises it, with the cancel itself still on its way.
    cancellation.raise()
    await lines.receive(["hello"])

    await #expect(throws: CancellationError.self) {
      try await waiting.value
    }
    #expect(try await lines.next(cancellation: CancellationFlag()) == "hello")
  }

  @Test
  func `a wait cancelled before its cancel reaches the lines throws when they end`() async {
    let lines = ChildSignalLines()
    let cancellation = CancellationFlag()
    let waiting = Task {
      try await lines.wait(
        ticket: 0,
        cancellation: cancellation,
      )
    }

    await lines.nextWaiter()
    cancellation.raise()
    await lines.finish()

    await #expect(throws: CancellationError.self) {
      try await waiting.value
    }
  }

  @Test
  func `a wait whose cancel came before it began throws at once`() async {
    let lines = ChildSignalLines()
    let cancellation = CancellationFlag()

    cancellation.raise()

    await #expect(throws: CancellationError.self) {
      try await lines.wait(
        ticket: 0,
        cancellation: cancellation,
      )
    }
  }

  @Test
  func `a signal whose path is taken says which call failed`() throws {
    let first = try signal()
    defer {
      first.close()
    }

    let failure = #expect(throws: NamedPipeFailure.self) {
      try signal()
    }

    #expect(failure?.call == "mkfifo")
    #expect(failure?.path == fixture.location(of: "said.fifo").path)
  }
}
