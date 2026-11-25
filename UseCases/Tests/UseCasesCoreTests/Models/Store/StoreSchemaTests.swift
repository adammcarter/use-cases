import Testing
@testable import UseCasesCore

struct StoreSchemaTests {
  @Test(arguments: [
    (StoreSchema.run, "run.schema.json"),
    (.result, "result.schema.json"),
    (.completion, "completion.schema.json"),
    (.start, "start.schema.json"),
    (.runOrder, "run-order.schema.json"),
  ])
  func `each schema is named for its file`(
    schema: StoreSchema,
    fileName: String,
  ) {
    #expect(schema.fileName == fileName)
  }

  @Test
  func `the shared definitions are a file of their own`() {
    #expect(StoreSchema.commonFileName == "common.schema.json")
    #expect(StoreSchema.allCases.count == 5)
  }
}
