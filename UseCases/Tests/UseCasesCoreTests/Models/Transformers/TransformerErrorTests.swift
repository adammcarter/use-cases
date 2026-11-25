import Testing
@testable import UseCasesCore

struct TransformerErrorTests {
  @Test(
    arguments: [
      (
        TransformerError.timedOut(name: "tools/slow", after: .seconds(120)),
        "tools/slow did not finish within 120 seconds",
      ),
      (
        TransformerError.timedOut(name: "junit", after: .seconds(2)),
        "junit did not finish within 2 seconds",
      ),
      (
        TransformerError.exited(name: "tools/x", code: 3, console: ""),
        "tools/x exited 3",
      ),
      (
        TransformerError.exited(name: "tools/x", code: 3, console: "boom"),
        "tools/x exited 3: boom",
      ),
      (
        TransformerError.signaled(name: "tools/x", signal: 9),
        "tools/x was terminated abnormally (signal 9)",
      ),
      (
        TransformerError.couldNotLaunch(name: "tools/x", reason: "Permission denied"),
        "tools/x could not be launched: Permission denied",
      ),
      (
        TransformerError.malformedResponse(name: "tools/x", reason: "response.json is not JSON"),
        "tools/x wrote malformed output: response.json is not JSON",
      ),
      (
        TransformerError.unsupportedContract(name: "tools/x"),
        "tools/x did not answer with contract 1",
      ),
      (
        TransformerError.badLink(
          name: "tools/x",
          link: "{\"file\":\"a\"}",
          problem: .validationNeedsRoute,
        ),
        "tools/x returned a bad link {\"file\":\"a\"}: a validation link needs a route",
      ),
      (TransformerError.cancelled, "cancelled"),
    ],
  )
  func `each error is told in the words the suite pins, starting with the name`(
    error: TransformerError,
    words: String,
  ) {
    #expect(error.description == words)
  }

  @Test
  func `a bundled program that is missing is told as one that could not be launched`() {
    let error = TransformerError.programMissing(
      name: "junit",
      expectedAt: "/opt/use-cases/use-cases-transformers",
    )

    #expect(error.description.hasPrefix("junit could not be launched: "))
    #expect(error.description.hasSuffix("/opt/use-cases/use-cases-transformers"))
  }

  @Test
  func `a private folder that cannot be made is told with the reason`() {
    let error = TransformerError.scratchUnavailable(name: "junit", reason: "disk full")

    #expect(error.description.hasPrefix("junit could not be run"))
    #expect(error.description.hasSuffix("disk full"))
  }
}
