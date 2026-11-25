import Testing
@testable import UseCasesCore

struct AuthoredSchemaTests {
  @Test(arguments: [
    (AuthoredSchema.workspace, "workspace.schema.json"),
    (.useCases, "use-cases.schema.json"),
    (.useCaseGroups, "use-case-groups.schema.json"),
    (.bridge, "bridge.schema.json"),
  ])
  func `each schema is named for its file`(
    schema: AuthoredSchema,
    fileName: String,
  ) {
    #expect(schema.fileName == fileName)
  }

  @Test
  func `there are four schemas`() {
    #expect(AuthoredSchema.allCases.count == 4)
  }
}
