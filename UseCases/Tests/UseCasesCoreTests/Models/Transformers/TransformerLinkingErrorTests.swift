import Testing
@testable import UseCasesCore

struct TransformerLinkingErrorTests {
  @Test
  func `a cancellation stays a cancellation`() {
    #expect(TransformerLinkingError(TransformerError.cancelled) == .cancelled)
    #expect(TransformerLinkingError.cancelled.message == "cancelled")
  }

  @Test(
    arguments: [
      TransformerError.timedOut(name: "tools/x", after: .seconds(120)),
      .exited(name: "tools/x", code: 1, console: "no"),
      .couldNotLaunch(name: "tools/x", reason: "gone"),
      .programMissing(name: "junit", expectedAt: "/x/use-cases-transformers"),
    ],
  )
  func `every other error is a failure that carries its words`(error: TransformerError) {
    let linking = TransformerLinkingError(error)

    #expect(linking == .failed(message: error.description))
    #expect(linking.message == error.description)
  }
}
