import Testing
@testable import UseCasesCore

struct GuidePlanParametersTests {
  private func plan() throws -> GuidePlan {
    try GuideFixture.plan(
      "\"need quotes\" stale -verdict",
      isExact: true,
      pageSize: 5,
      offset: 10,
    )
  }

  @Test
  func `the parameters name the command and everything the plan says`() throws {
    let parameters = try plan().parameters

    #expect(parameters == .members([
      "words": .strings(["stale"]),
      "phrases": .array([.strings(["need", "quotes"])]),
      "exclusions": .array([.strings(["verdict"])]),
      "exact": .boolean(true),
      "command": .string("docs"),
      "version": .integer(1),
      "page_size": .integer(5),
      "offset": .integer(10),
    ]))
  }

  @Test
  func `a plan reads back from the document it was written to`() throws {
    let original = try plan()
    let document = SearchTokenCodec().token(for: original.document(sealedBy: "abc"))
    let value = try SearchTokenCodec().parameters(in: document)

    let back = try GuidePlan(reading: AuthoredObject(value, at: ""))

    #expect(back == GuidePlan(
      query: original.query,
      pageSize: 5,
      offset: 10,
      seal: "abc",
    ))
  }

  @Test
  func `moving a plan keeps the search and drops the seal`() throws {
    let moved = try plan().moved(to: 15)

    #expect(moved.offset == 15)
    #expect(moved.pageSize == 5)
    #expect(moved.seal == nil)
  }

  @Test(arguments: [
    #"{"command":"search","version":1,"page_size":1,"offset":0,"seal":"s"}"#,
    #"{"version":1,"page_size":1,"offset":0,"seal":"s"}"#,
    #"{"command":"docs","version":2,"page_size":1,"offset":0,"seal":"s"}"#,
    #"{"command":"docs","version":1,"offset":0,"seal":"s"}"#,
    #"{"command":"docs","version":1,"page_size":1,"offset":0}"#,
    #"{"command":"docs","version":1,"page_size":1,"offset":0,"seal":"s","words":"x"}"#,
  ])
  func `parameters that are not a docs token's are refused`(json: String) throws {
    let value = try JSONReader().read(json)

    #expect(throws: AuthoredShapeError.self) {
      try GuidePlan(reading: AuthoredObject(value, at: ""))
    }
  }
}
