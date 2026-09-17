import Testing
@testable import UseCasesCore

/// The canonical id pattern is the single guard that keeps a user-supplied id
/// from becoming a path-traversal segment, so its edges are pinned explicitly.
struct CanonicalIdentifierTests {
  @Test(arguments: [
    "a",
    "a1",
    "0a",
    "a-b",
    "a_b",
    "a.b",
    "a.b.c",
    "use-cases",
    "capsule.demos.persisted_smoke_runbook",
    "showcase.flow.revision_epoch_staleness",
  ])
  func `accepts a canonical identifier`(value: String) {
    #expect(CanonicalIdentifier.isValid(value))
  }

  @Test(arguments: [
    "",
    "A",
    "Abc",
    "aBc",
    "-a",
    "_a",
    ".a",
    "a.",
    "a..b",
    "a/b",
    "a\\b",
    "..",
    ".",
    "a b",
    "/a",
    "a/../b",
    "a:b",
    "a#b",
  ])
  func `refuses a non-canonical identifier`(value: String) {
    #expect(!CanonicalIdentifier.isValid(value))
  }

  @Test
  func `a valid identifier passes the assertion unchanged`() throws {
    try CanonicalIdentifier.assertValid("capsule.demos", parameterName: "row")
  }

  @Test
  func `an invalid identifier throws a stable path error`() throws {
    #expect(throws: PathError.invalidIdentifier(parameterName: "row", value: "../etc")) {
      try CanonicalIdentifier.assertValid("../etc", parameterName: "row")
    }
  }

  @Test
  func `the invalid identifier error carries the contract code`() {
    let error = PathError.invalidIdentifier(parameterName: "row", value: "../etc")
    #expect(error.code == "path.invalid_id")
  }

  @Test
  func `the escape error carries the contract code`() {
    #expect(PathError.escape("out of bounds").code == "path.escape")
  }
}
