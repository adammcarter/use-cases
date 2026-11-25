import Testing
@testable import UseCasesCore

struct GuidePlannerTests {
  private let planner = GuidePlanner()

  @Test
  func `words are a new search of the first page, 20 to a page`() throws {
    let plan = try planner.plan(
      words: "\"need quotes\" -gotchas stale",
      isExact: true,
      pageSize: nil,
    )

    #expect(plan.query.words == ["stale"])
    #expect(plan.query.phrases == [["need", "quotes"]])
    #expect(plan.query.exclusions == [["gotchas"]])
    #expect(plan.query.isExact)
    #expect(plan.pageSize == 20)
    #expect(plan.offset == 0)
    #expect(plan.seal == nil)
  }

  @Test(arguments: ["1", "20", "100"])
  func `a page size from 1 to 100 is taken`(size: String) throws {
    let plan = try planner.plan(
      words: "x",
      isExact: false,
      pageSize: size,
    )

    #expect(plan.pageSize == Int(size))
  }

  @Test(arguments: ["", "0", "101", "-1", "+5", "1.5", "many", "٣", " 5"])
  func `any other page size is refused`(size: String) {
    #expect(throws: GuideSearchError.pageSize(size)) {
      try planner.plan(
        words: "x",
        isExact: false,
        pageSize: size,
      )
    }
  }

  @Test
  func `an unclosed quote and words with nothing to look for are refused`() {
    #expect(throws: GuideSearchError.words(.unclosedQuote)) {
      try planner.plan(
        words: "\"never closed",
        isExact: false,
        pageSize: nil,
      )
    }
    #expect(throws: GuideSearchError.words(.noWords)) {
      try planner.plan(
        words: "-gotchas",
        isExact: false,
        pageSize: nil,
      )
    }
  }

  @Test
  func `a token the searcher made is read back as the plan of the following page`() throws {
    let searcher = GuideSearcher()
    let plan = try planner.plan(
      words: "stale",
      isExact: false,
      pageSize: "1",
    )
    let page = try searcher.search(
      plan,
      in: GuideFixture.all,
    )

    let token = try #require(page.next)
    let next = try planner.plan(continuing: token)

    #expect(next.query == plan.query)
    #expect(next.pageSize == 1)
    #expect(next.offset == 1)
    #expect(next.seal != nil)
  }

  @Test(arguments: ["", "garbage", "eyJ2IjoyfQ", "ZXhhbXBsZQ"])
  func `text that is not a token is refused`(token: String) {
    #expect(throws: GuideSearchError.invalidToken) {
      try planner.plan(continuing: token)
    }
  }

  @Test
  func `a token of search is not a token of docs`() throws {
    let codec = SearchTokenCodec()
    let search = SearchPlan(
      query: SearchQuery(
        words: ["the"],
        phrases: [],
        exclusions: [],
        isExact: false,
      ),
      filters: SearchFilters(
        under: nil,
        group: nil,
        tiers: [],
        states: [],
        excluded: nil,
      ),
      fields: SearchField.allCases,
      wantsFull: false,
      pageSize: 1,
      offset: 1,
      seal: nil,
    )
    let token = codec.token(for: search.document(sealedBy: "seal"))

    #expect(throws: GuideSearchError.invalidToken) {
      try planner.plan(continuing: token)
    }
  }

  @Test
  func `a token that was edited is refused, even by a change that reads the same`() throws {
    let codec = SearchTokenCodec()
    let plan = try GuideFixture.plan("the")
    let extra = StoreJSONValue.object(
      plan.parameters.members + [
        StoreJSONMember(key: "seal", value: .string("seal")),
        StoreJSONMember(key: "note", value: .string("added")),
      ],
    )

    #expect(throws: GuideSearchError.invalidToken) {
      try planner.plan(continuing: codec.token(for: extra))
    }
  }

  @Test(arguments: [(1, -1), (101, 0), (0, 0)])
  func `a token with an offset or page size out of range is refused`(
    size: Int,
    offset: Int,
  ) throws {
    let plan = try GuideFixture.plan(
      "the",
      pageSize: size,
      offset: offset,
    )
    let token = SearchTokenCodec().token(for: plan.document(sealedBy: "seal"))

    #expect(throws: GuideSearchError.invalidToken) {
      try planner.plan(continuing: token)
    }
  }
}

private extension StoreJSONValue {
  var members: [StoreJSONMember] {
    guard case let .object(members) = self else {
      return []
    }

    return members
  }
}
