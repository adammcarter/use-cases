import Testing
@testable import UseCasesCore

struct UseCaseBatchTests {
  private func batch(_ json: String) throws -> UseCaseBatch {
    try BatchFixture().batch(json)
  }

  @Test
  func `a batch with each use case once is fine`() throws {
    try batch(
      #"{"remove": ["app.solo.only"], "save": [{"id": "app.dark.toggle", "title": "T"}]}"#,
    ).requireEachOnce()
  }

  @Test(arguments: [
    (#"{"remove": ["app.solo.only", "app.solo.only"]}"#, "app.solo.only"),
    (
      #"""
      {"save": [{"id": "app.dark.toggle", "title": "A"},
                {"id": "app.dark.toggle", "title": "B"}]}
      """#,
      "app.dark.toggle",
    ),
    (
      #"{"remove": ["app.dark.toggle"], "save": [{"id": "app.dark.toggle", "title": "B"}]}"#,
      "app.dark.toggle",
    ),
  ])
  func `a use case in the batch twice is refused, removing and saving one included`(
    json: String,
    repeated: String,
  ) throws {
    let batch = try batch(json)

    #expect(throws: UseCaseBatchError.repeated(identifier: repeated)) {
      try batch.requireEachOnce()
    }
  }
}
