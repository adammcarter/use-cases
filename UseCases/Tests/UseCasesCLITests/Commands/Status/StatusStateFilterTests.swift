import Testing
import UseCasesCore
@testable import UseCasesCLI

struct StatusStateFilterTests {
  @Test
  func `one state is read`() throws {
    let filter = try StatusStateFilter(parsing: "failed")

    #expect(filter.states == [.failed])
  }

  @Test
  func `several states are read, spaces around a word do not matter`() throws {
    let filter = try StatusStateFilter(parsing: "failed, stale ,draft")

    #expect(filter.states == [.failed, .stale, .draft])
    #expect(filter.contains(.stale))
    #expect(!filter.contains(.verified))
  }

  @Test
  func `a state named twice is one`() throws {
    #expect(try StatusStateFilter(parsing: "error,error").states == [.error])
  }

  @Test(arguments: VerificationStatus.allCases)
  func `every state can be asked for`(state: VerificationStatus) throws {
    #expect(try StatusStateFilter(parsing: state.rawValue).states == [state])
  }

  @Test(arguments: [
    ("broken", ["broken"]),
    ("failed,broken,worse", ["broken", "worse"]),
    ("", [""]),
    ("failed,", [""]),
    ("FAILED", ["FAILED"]),
  ])
  func `a word that is no state is refused, with every such word named`(
    text: String,
    unknown: [String],
  ) {
    #expect(throws: StatusStateFilterError.unknown(unknown)) {
      try StatusStateFilter(parsing: text)
    }
  }

  @Test
  func `the refusal names the words and the states there are`() {
    let message = StatusStateFilterError.unknown(["broken"]).message

    #expect(message.contains("unknown: broken"))
    #expect(message.contains("failed, error, incomplete, unverified, stale, verified, draft"))
  }
}
