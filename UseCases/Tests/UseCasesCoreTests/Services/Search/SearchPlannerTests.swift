import Foundation
import Testing
@testable import UseCasesCore

struct SearchPlannerTests {
  private let folder: TemporaryDirectory
  private let planner: SearchPlanner

  init() throws {
    folder = try TemporaryDirectory()
    planner = SearchPlanner(workingDirectory: folder.url)
  }

  private func plan(
    _ subject: SearchSubject,
    under: String? = nil,
    tiers: String? = nil,
    states: String? = nil,
    fields: String? = nil,
    pageSize: String? = nil,
  ) throws(UseCaseSearchError) -> SearchPlan {
    try planner.plan(
      .new(
        SearchOptions(
          subject: subject,
          under: under,
          tiers: tiers,
          states: states,
          fields: fields,
          pageSize: pageSize,
        ),
      ),
    )
  }

  @Test
  func `a new search starts at the first page of 20, in every field`() throws {
    let plan = try plan(.words("double tap"))

    #expect(plan.offset == 0)
    #expect(plan.pageSize == 20)
    #expect(plan.fields == SearchField.allCases)
    #expect(plan.seal == nil)
    #expect(plan.query.words == ["double", "tap"])
  }

  @Test
  func `fields, tiers and states are read as comma separated lists`() throws {
    let plan = try plan(
      .words("tap"),
      tiers: "critical, core",
      states: "failed,draft",
      fields: "title,id",
    )

    #expect(plan.fields == [.id, .title])
    #expect(plan.filters.tiers == [.critical, .core])
    #expect(plan.filters.states == [.failed, .draft])
  }

  @Test
  func `a field, tier or state there is not is refused, naming what it takes`() {
    #expect(throws: UseCaseSearchError.unknownFields(["tags"])) {
      try plan(.words("x"), fields: "title,tags")
    }
    #expect(throws: UseCaseSearchError.unknownTiers(["urgent"])) {
      try plan(.words("x"), tiers: "urgent")
    }
    #expect(throws: UseCaseSearchError.unknownStates(["green", ""])) {
      try plan(.words("x"), states: "green,failed,")
    }
  }

  @Test
  func `a like use case is read leniently and never matches itself`() throws {
    try folder.write(
      "draft.yml",
      "id: app.a.b\ntitle: \"Tap \\\"twice\\\"\"\nscenarios:\n  - id: s\n    when: [One tap]\n",
    )

    let plan = try plan(.like("draft.yml"))

    #expect(plan.query.words == ["tap", "twice", "one"])
    #expect(plan.query.phrases.isEmpty)
    #expect(plan.filters.excluded == "app.a.b")
  }

  @Test
  func `a like use case with no text is refused`() throws {
    try folder.write("draft.yml", "id: app.x.y\n")

    #expect(throws: UseCaseSearchError.likeHasNoText) {
      try plan(.like("draft.yml"))
    }
  }

  @Test
  func `a like file that is not there is refused with why`() {
    let thrown = #expect(throws: UseCaseSearchError.self) {
      try plan(.like("missing.yml"))
    }

    #expect(thrown?.message.contains("missing.yml") == true)
  }

  @Test
  func `a like input that is not a mapping is refused`() throws {
    try folder.write("list.yml", "- a\n- b\n")

    let thrown = #expect(throws: UseCaseSearchError.self) {
      try plan(.like("list.yml"))
    }

    #expect(thrown?.message.contains("not a mapping") == true)
  }

  @Test(arguments: ["garbage", "", "eyJ2IjoyfQ", "e30", "W10", "bnVsbA", "eyJ2ZXJzaW9uIjoxfQ"])
  func `a token that is not one a search made is refused`(token: String) {
    #expect(throws: UseCaseSearchError.invalidToken) {
      try planner.plan(.continuing(token: token))
    }
  }

  @Test
  func `a token carries the plan, its position and its seal`() throws {
    let first = try plan(
      .words("double -zoom \"to like\""),
      tiers: "core",
      fields: "title",
      pageSize: "3",
    )
    let token = SearchTokenCodec().token(
      for: first.moved(to: 6).document(sealedBy: "abc"),
    )

    let read = try planner.plan(.continuing(token: token))

    #expect(read.query == first.query)
    #expect(read.filters == first.filters)
    #expect(read.fields == [.title])
    #expect(read.pageSize == 3)
    #expect(read.offset == 6)
    #expect(read.seal == "abc")
  }

  @Test
  func `a token with something added or a number out of range is refused`() throws {
    let first = try plan(.words("tap"))
    let codec = SearchTokenCodec()
    let good = first.document(sealedBy: "abc")

    guard case let .object(members) = good else {
      Issue.record("not an object")
      return
    }

    let extra = StoreJSONValue.object(
      members + [StoreJSONMember(key: "extra", value: .boolean(true))],
    )
    let negative = StoreJSONValue.object(
      members.map { member in
        member.key == "offset" ? StoreJSONMember(key: "offset", value: .integer(-1)) : member
      },
    )
    let huge = StoreJSONValue.object(
      members.map { member in
        member.key == "page_size" ? StoreJSONMember(key: "page_size", value: .integer(101)) : member
      },
    )

    for forged in [extra, negative, huge] {
      #expect(throws: UseCaseSearchError.invalidToken) {
        try planner.plan(.continuing(token: codec.token(for: forged)))
      }
    }

    #expect(throws: Never.self) {
      try planner.plan(.continuing(token: codec.token(for: good)))
    }
  }
}
