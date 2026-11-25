import Testing
@testable import UseCasesCore

struct SearchPlanParametersTests {
  private func plan() -> SearchPlan {
    SearchPlan(
      query: SearchQuery(
        words: ["double"],
        phrases: [["to", "like"]],
        exclusions: [["zoom"]],
        isExact: true,
      ),
      filters: SearchFilters(
        under: "app.feed",
        group: nil,
        tiers: [.critical],
        states: [.failed, .draft],
        excluded: "app.feed.post.like",
      ),
      fields: [.title, .scenarios],
      wantsFull: true,
      pageSize: 5,
      offset: 10,
      seal: nil,
    )
  }

  @Test
  func `the parameters are the same compact JSON every time`() {
    let writer = StoreJSONWriter()
    let text = String(bytes: writer.compact(plan().parameters), encoding: .utf8)

    #expect(
      text == #"{"exact":true,"excluded":"app.feed.post.like","exclusions":[["zoom"]],"#
        + #""fields":["title","scenarios"],"full":true,"offset":10,"page_size":5,"#
        + #""phrases":[["to","like"]],"states":["failed","draft"],"tiers":["critical"],"#
        + #""under":"app.feed","version":1,"words":["double"]}"#,
    )
  }

  @Test
  func `a group and a missing under are left out, never null`() {
    let moved = plan().moved(to: 0)
    let text = String(bytes: StoreJSONWriter().compact(moved.parameters), encoding: .utf8)

    #expect(text?.contains("\"group\"") == false)
  }

  @Test
  func `the plan reads back from its document`() throws {
    let original = plan()
    let document = original.document(sealedBy: "seal")
    let value = try AuthoredValue.json(
      #require(String(bytes: StoreJSONWriter().compact(document), encoding: .utf8)),
    )

    let read = try SearchPlan(reading: AuthoredObject(value, at: ""))

    #expect(read.query == original.query)
    #expect(read.filters == original.filters)
    #expect(read.fields == original.fields)
    #expect(read.wantsFull)
    #expect(read.pageSize == 5)
    #expect(read.offset == 10)
    #expect(read.seal == "seal")
  }

  @Test
  func `moving a plan keeps the search and drops the seal`() {
    let moved = plan().moved(to: 15)

    #expect(moved.offset == 15)
    #expect(moved.query == plan().query)
    #expect(moved.seal == nil)
  }

  @Test(arguments: [
    #"{"version": 2}"#,
    #"{"version": 1}"#,
    #"{"version": 1, "words": [1], "page_size": 1, "offset": 0, "seal": "x"}"#,
    #"{"version": 1, "words": [], "phrases": [1], "page_size": 1, "offset": 0, "seal": "x"}"#,
    #"{"version": 1, "words": [], "tiers": ["urgent"], "page_size": 1, "offset": 0, "seal": "x"}"#,
    #"{"version": 1, "words": [], "phrases": [[1]], "page_size": 1, "offset": 0, "seal": "x"}"#,
  ])
  func `parameters of another shape are refused`(json: String) throws {
    let value = try AuthoredValue.json(json)

    #expect(throws: AuthoredShapeError.self) {
      try SearchPlan(reading: AuthoredObject(value, at: ""))
    }
  }
}
