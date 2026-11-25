import Testing
@testable import UseCasesCore

struct ValidationTypeWordsTests {
  @Test(arguments: [
    (ValidationType.unit, "unit tests"),
    (.integration, "integration tests"),
    (.contract, "contract tests"),
    (.snapshot, "snapshot tests"),
    (.userInterface, "UI tests"),
    (.e2e, "end-to-end tests"),
    (.acceptance, "trying it"),
    (.performance, "performance checks"),
  ])
  func `a kind of route is told in words a person reads`(
    type: ValidationType,
    words: String,
  ) {
    #expect(type.words == words)
  }

  @Test
  func `a custom kind is told by the name its author gave it`() throws {
    #expect(try ValidationType.custom(name: IdentifierSegment(validating: "load-test"))
      .words == "load-test")
  }
}
