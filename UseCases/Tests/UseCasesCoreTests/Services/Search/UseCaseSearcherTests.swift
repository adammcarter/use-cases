import Foundation
import Testing
@testable import UseCasesCore

struct UseCaseSearcherTests {
  private let fixture: SearchFixture

  init() throws {
    fixture = try SearchFixture()
  }

  private func found(
    _ words: String,
    under: String? = nil,
    group: String? = nil,
    tiers: String? = nil,
    states: String? = nil,
    fields: String? = nil,
    isExact: Bool = false,
  ) throws -> [String] {
    try fixture.found(
      .words(words),
      under: under,
      group: group,
      tiers: tiers,
      states: states,
      fields: fields,
      isExact: isExact,
    )
  }

  @Test
  func `a title ranks above a scenario or an out of scope, and ties go by id`() throws {
    #expect(try found("double tap") == [
      "app.feed.post.like", "app.feed.media.zoom", "app.feed.post.unlike",
    ])
  }

  @Test
  func `within one field weight an exact word outranks a word start`() throws {
    let page = try fixture.page(.words("double tap"))
    let scores = page.matches.map(\.score)

    #expect(scores == scores.sorted(by: >))
    #expect(page.matches[0].score == 1.0)
    #expect(page.matches[1].score > page.matches[2].score)
  }

  @Test
  func `a match says every place it matched, strongest first, with where`() throws {
    let like = try #require(fixture.page(.words("double tap")).matches.first)

    #expect(like.reasons.first == SearchReason(
      field: .title,
      location: nil,
      text: "Double tap to like a post",
    ))
    #expect(like.reasons.contains(SearchReason(
      field: .scenarios,
      location: "main",
      text: "The user taps a post twice",
    )))
    #expect(like.status == .unverified)
    #expect(like.valueTier == "critical")
    #expect(like.file == "use-cases/feed/post.yml")
  }

  @Test
  func `typos and word starts are forgiven unless exact`() throws {
    #expect(try found("phtoo").contains("app.feed.media.zoom"))
    #expect(try found("phtoo", isExact: true).isEmpty)
    #expect(try found("lik").contains("app.feed.post.like"))
  }

  @Test
  func `a phrase must appear as written, even beside other words`() throws {
    #expect(try found("\"double tap\"") == ["app.feed.post.like", "app.feed.media.zoom"])
    #expect(try found("\"double taps\"").contains("app.feed.post.unlike"))
    #expect(try found("\"tap double\"").isEmpty)
    #expect(try found("double \"pinches a photo\"") == ["app.feed.media.zoom"])
  }

  @Test
  func `a minus word leaves use cases out`() throws {
    #expect(try found("double").contains("app.feed.media.zoom"))
    #expect(try !found("double -zoom").contains("app.feed.media.zoom"))
    #expect(try !found("double -\"to zoom\"").contains("app.feed.media.zoom"))
  }

  @Test
  func `nothing found is an empty page`() throws {
    let page = try fixture.page(.words("spaceship"))

    #expect(page == SearchPage(
      total: 0,
      offset: 0,
      pageSize: 20,
      matches: [],
      next: nil,
    ))
  }

  @Test
  func `in limits the fields searched`() throws {
    #expect(try found("zoom", fields: "out_of_scope") == ["app.feed.media.zoom"])
    #expect(try found("twice", fields: "title").isEmpty)
    #expect(try found("twice", fields: "scenarios") == ["app.feed.post.like"])
    #expect(try !found("manual", fields: "validation").isEmpty)
    #expect(try found("zoom", fields: "id, out_of_scope") == ["app.feed.media.zoom"])
  }

  @Test
  func `filters keep what they name, all together, any value of one`() throws {
    #expect(try found("the", under: "app.feed.post") == [
      "app.feed.post.like", "app.feed.post.unlike",
    ])
    #expect(try found("the", group: "social") == ["app.feed.post.like", "app.feed.post.unlike"])
    #expect(try found("the", tiers: "critical") == ["app.feed.post.like"])
    #expect(try found("a", tiers: "critical,supporting") == [
      "app.feed.post.like", "app.settings.theme",
    ])
    #expect(try found("theme", states: "draft") == ["app.settings.theme"])
    #expect(try found("theme", states: "verified").isEmpty)
    #expect(try found("the", under: "app.feed", tiers: "core") == [
      "app.feed.media.zoom", "app.feed.post.unlike",
    ])
  }

  @Test
  func `a use case with no tier is not kept by a tier filter`() throws {
    try fixture.workspace.write(
      "use-cases/notier.yml",
      "prefix: notier\nuse_cases:\n  - id: bare\n    title: Bare thing\n",
    )

    #expect(try found("bare") == ["app.notier.bare"])
    #expect(try found("bare", tiers: "core,critical,supporting").isEmpty)
  }

  @Test(arguments: [
    (["--under", "app.nope"], "no use case or id prefix"),
    (["--group", "nope"], "no group"),
  ])
  func `a filter that names nothing is refused in the words of its source`(
    flag: [String],
    message: String,
  ) throws {
    let thrown = #expect(throws: UseCaseSearchError.self) {
      try fixture.page(
        .words("tap"),
        under: flag.first == "--under" ? flag[1] : nil,
        group: flag.first == "--group" ? flag[1] : nil,
      )
    }

    #expect(thrown?.message.contains(message) == true)
  }

  @Test
  func `full carries exactly what show returns`() throws {
    let match = try #require(fixture.page(
      .words("zoom"),
      wantsFull: true,
    ).matches.first)
    let loaded = try fixture.workspace.loaded()
    let shown = try UseCaseShower().show(
      match.identifier,
      in: loaded,
    )

    #expect(match.definition == shown.definition)
    #expect(try fixture.page(.words("zoom")).matches.first?.definition == nil)
  }

  @Test
  func `the same search gives the same answer`() throws {
    #expect(try fixture.page(.words("the user")) == fixture.page(.words("the user")))
  }

  @Test
  func `like finds use cases like a draft and never itself`() throws {
    let draft = fixture.workspace.directory.location(of: "draft.yml")
    try Data(
      """
      id: app.feed.post.like
      title: Tap a photo twice to like it
      scenarios:
        - id: s
          when: [The user taps a photo twice]\n
      """.utf8,
    ).write(to: draft)

    let result = try fixture.found(.like(draft.path))

    #expect(!result.contains("app.feed.post.like"))
    #expect(["app.feed.media.zoom", "app.feed.post.unlike"].contains(result[0]))
  }

  @Test
  func `like without an id of its own may find any use case`() throws {
    let draft = fixture.workspace.directory.location(of: "draft.json")
    try Data(#"{"title": "Zoom into a photo"}"#.utf8).write(to: draft)

    #expect(try fixture.found(.like(draft.path)).first == "app.feed.media.zoom")
  }
}
