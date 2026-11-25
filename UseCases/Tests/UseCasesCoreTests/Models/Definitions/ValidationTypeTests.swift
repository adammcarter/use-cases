import Testing
@testable import UseCasesCore

struct ValidationTypeTests {
  private func type(_ json: String) throws -> ValidationType {
    try ValidationType(authored: AuthoredObject(authored(json), at: "type"))
  }

  @Test(
    arguments: [
      ("unit", ValidationType.unit),
      ("integration", ValidationType.integration),
      ("contract", ValidationType.contract),
      ("snapshot", ValidationType.snapshot),
      ("ui", ValidationType.userInterface),
      ("e2e", ValidationType.e2e),
      ("acceptance", ValidationType.acceptance),
      ("performance", ValidationType.performance),
    ],
  )
  func `each built-in kind is read`(
    case example: (kind: String, type: ValidationType),
  ) throws {
    let json = JSONMembers(["kind": jsonString(example.kind)]).json

    #expect(try type(json) == example.type)
  }

  @Test
  func `a custom kind carries its name`() throws {
    let type = try type(#"{"kind":"custom","name":"accessibility"}"#)

    let name = try IdentifierSegment(validating: "accessibility")
    #expect(type == .custom(name: name))
  }

  @Test(
    arguments: [
      #"{"kind":"custom"}"#,
      #"{"kind":"custom","name":"Not Valid"}"#,
      #"{"kind":"smoke"}"#,
      "{}",
    ],
  )
  func `a kind that is unknown or lacks its name is refused`(json: String) {
    #expect(throws: AuthoredShapeError.self) {
      try type(json)
    }
  }
}
