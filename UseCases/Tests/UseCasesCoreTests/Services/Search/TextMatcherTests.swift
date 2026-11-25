import Testing
@testable import UseCasesCore

struct TextMatcherTests {
  private let matcher = TextMatcher()

  private func passage(
    _ text: String,
    weight: Int = 10,
  ) -> SearchPassage {
    SearchPassage(
      weight: weight,
      text: text,
    )
  }

  private func query(
    _ words: [String] = [],
    phrases: [[String]] = [],
    exclusions: [[String]] = [],
    isExact: Bool = false,
  ) -> SearchQuery {
    SearchQuery(
      words: words,
      phrases: phrases,
      exclusions: exclusions,
      isExact: isExact,
    )
  }

  private func match(
    _ query: SearchQuery,
    _ passages: [SearchPassage],
  ) -> TextMatch? {
    matcher.match(
      query,
      in: passages,
    )
  }

  @Test
  func `an exact word outranks a word start outranks a typo`() throws {
    let exact = try #require(match(query(["tap"]), [passage("tap")]))
    let start = try #require(match(query(["tap"]), [passage("taps")]))
    let typo = try #require(match(query(["tapp"]), [passage("tap")]))

    #expect(exact.points == 1000)
    #expect(start.points == 700)
    #expect(typo.points == 450)
    #expect(exact.score > start.score)
    #expect(start.score > typo.score)
  }

  @Test
  func `a word start counts only for a query word of three letters or more`() {
    #expect(match(query(["ta"]), [passage("tap")]) == nil)
    #expect(match(query(["tap"]), [passage("taps")]) != nil)
  }

  @Test
  func `the typos forgiven follow the length of the query word`() {
    #expect(match(query(["tap"]), [passage("tip")]) == nil)
    #expect(match(query(["tapp"]), [passage("tipp")]) != nil)
    #expect(match(query(["tapp"]), [passage("tipx")]) == nil)
    #expect(match(query(["doubling"]), [passage("doublxxg")]) != nil)
    #expect(match(query(["doubling"]), [passage("doubxxxg")]) == nil)
  }

  @Test
  func `two typos in a long word score less than one`() throws {
    let one = try #require(match(query(["doubling"]), [passage("doublinx")]))
    let two = try #require(match(query(["doubling"]), [passage("doublixx")]))

    #expect(one.points == 450)
    #expect(two.points == 300)
  }

  @Test
  func `exact turns off word starts and typos`() {
    let exact = query(["lik"], isExact: true)

    #expect(match(exact, [passage("like")]) == nil)
    #expect(match(query(["phtoo"], isExact: true), [passage("photo")]) == nil)
    #expect(match(query(["like"], isExact: true), [passage("Like")]) != nil)
  }

  @Test
  func `a heavier passage counts more than a lighter one`() throws {
    let found = try #require(match(
      query(["tap"]),
      [passage("tap", weight: 3), passage("tap", weight: 10)],
    ))

    #expect(found.points == 1000)
    #expect(found.hits == [
      PassageHit(index: 1, strength: 1000),
      PassageHit(index: 0, strength: 300),
    ])
  }

  @Test
  func `equal passages are told in the order given`() throws {
    let found = try #require(match(query(["tap"]), [passage("tap"), passage("tap")]))

    #expect(found.hits.map(\.index) == [0, 1])
  }

  @Test
  func `a use case matches when any word does, and more words score more`() throws {
    let one = try #require(match(query(["double", "spaceship"]), [passage("double tap")]))
    let both = try #require(match(query(["double", "tap"]), [passage("double tap")]))

    #expect(one.score == 5000)
    #expect(both.score == 10000)
    #expect(match(query(["spaceship"]), [passage("double tap")]) == nil)
  }

  @Test
  func `a phrase must appear as written, its words next to each other`() {
    let phrase = query(phrases: [["double", "tap"]])

    #expect(match(phrase, [passage("Double tap to like")]) != nil)
    #expect(match(phrase, [passage("tap double")]) == nil)
    #expect(match(phrase, [passage("double taps")]) == nil)
    #expect(match(phrase, [passage("double to tap")]) == nil)
    #expect(match(phrase, [passage("double"), passage("tap")]) == nil)
  }

  @Test
  func `a phrase is required beside words`() {
    let both = query(["double"], phrases: [["pinches", "a", "photo"]])

    #expect(match(both, [passage("double"), passage("pinches a photo")]) != nil)
    #expect(match(both, [passage("double")]) == nil)
    #expect(match(both, [passage("pinches a photo")]) == nil)
  }

  @Test
  func `a word or a phrase to leave out removes the use case`() {
    let passages = [passage("Zoom a photo"), passage("Double tap to zoom")]

    #expect(match(query(["double"], exclusions: [["zoom"]]), passages) == nil)
    #expect(match(query(["double"], exclusions: [["to", "zoom"]]), passages) == nil)
    #expect(match(query(["double"], exclusions: [["zoo"]]), passages) != nil)
    #expect(match(query(["double"], exclusions: [["zoom", "to"]]), passages) != nil)
  }

  @Test
  func `no passages is no match`() {
    #expect(match(query(["tap"]), []) == nil)
  }

  @Test
  func `the same query gives the same answer`() {
    let passages = [passage("double tap"), passage("taps", weight: 3)]

    #expect(match(query(["tap", "doubel"]), passages) == match(query(["tap", "doubel"]), passages))
  }
}
