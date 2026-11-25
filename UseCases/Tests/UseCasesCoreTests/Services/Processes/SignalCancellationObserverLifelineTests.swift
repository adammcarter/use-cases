import Testing
@testable import UseCasesCore

/// A program that started this one dying cancels it as a signal does, and shares the signals the
/// observer's other tests hold, so these run with them, one at a time.
extension SignalCancellationObserverTests {
  @Test
  func `the program that started this one dying cancels it, as a signal does`() async throws {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
    }
    let lifeline = try #require(ProcessLifeline(descriptor: pipe.readEnd))
    let ownership = SignalOwnership(inheritedLifeline: { lifeline })

    await ownership.take()
    #expect(await !ownership.isCancelled)

    pipe.closeWriteEnd()
    await pipe.writersGone()
    #expect(await ownership.isCancelled)

    await ownership.release()
    #expect(await !ownership.isCancelled)
  }

  @Test
  func `a process started with no lifeline is cancelled by signals only`() async {
    let ownership = SignalOwnership(inheritedLifeline: { nil })

    await ownership.take()
    #expect(await !ownership.isCancelled)

    ProcessSignalFlag.raise()
    #expect(await ownership.isCancelled)
    await ownership.release()
  }

  @Test
  func `a lifeline broken before anything holds the signals cancels nothing`() async throws {
    let pipe = TestPipe()
    defer {
      pipe.closeReadEnd()
    }
    let lifeline = try #require(ProcessLifeline(descriptor: pipe.readEnd))
    pipe.closeWriteEnd()
    let ownership = SignalOwnership(inheritedLifeline: { lifeline })

    #expect(await !ownership.isCancelled)
  }
}
