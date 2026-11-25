import Testing
@testable import UseCasesCore

struct RouteResourceTests {
  private func resource(_ json: String) throws -> RouteResource {
    try RouteResource(authored: AuthoredObject(authored(json), at: "resources[0]"))
  }

  @Test
  func `a file resource names one file`() throws {
    let resource = try resource(#"{"kind":"file","path":"fixtures/users.json"}"#)

    let path = try WorkspacePath(validating: "fixtures/users.json")
    #expect(resource == .file(path))
  }

  @Test
  func `a glob resource carries its pattern`() throws {
    let resource = try resource(#"{"kind":"glob","pattern":"schemas/**/*.json"}"#)

    let pattern = try PathPattern(validating: "schemas/**/*.json")
    #expect(resource == .glob(pattern))
  }

  @Test(
    arguments: [
      #"{"kind":"url","path":"x"}"#,
      #"{"kind":"glob","pattern":"a**"}"#,
      #"{"kind":"glob","pattern":"."}"#,
      #"{"kind":"glob","pattern":"/x"}"#,
      #"{"kind":"file","path":"a//b"}"#,
      #"{"kind":"file"}"#,
    ],
  )
  func `a resource of another kind or with a malformed path or pattern is refused`(json: String) {
    #expect(throws: AuthoredShapeError.self) {
      try resource(json)
    }
  }
}
