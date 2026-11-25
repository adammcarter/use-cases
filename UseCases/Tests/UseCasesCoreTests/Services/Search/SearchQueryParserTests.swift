import Testing
@testable import UseCasesCore

struct SearchQueryParserTests {
  private let parser = SearchQueryParser()

  private func query(_ text: String) throws -> SearchQuery {
    try parser.query(
      from: text,
      isExact: false,
    )
  }

  @Test
  func `words are lower case and split at punctuation`() throws {
    let query = try query("Double  tap-to Like")

    #expect(query.words == ["double", "tap", "to", "like"])
    #expect(query.phrases.isEmpty)
    #expect(query.exclusions.isEmpty)
  }

  @Test
  func `a quoted phrase is one phrase of its words`() throws {
    let query = try query("\"Double-tap to\" like")

    #expect(query.phrases == [["double", "tap", "to"]])
    #expect(query.words == ["like"])
  }

  @Test
  func `a minus leaves a word or a phrase out`() throws {
    let query = try query("double -zoom -\"to zoom\"")

    #expect(query.words == ["double"])
    #expect(query.exclusions == [["zoom"], ["to", "zoom"]])
  }

  @Test
  func `a minus on its own and a phrase with no words are nothing`() throws {
    let query = try query("tap - \"\" \"--\"")

    #expect(query.words == ["tap"])
    #expect(query.phrases.isEmpty)
    #expect(query.exclusions.isEmpty)
  }

  @Test
  func `exact is carried to the query`() throws {
    let query = try parser.query(
      from: "tap",
      isExact: true,
    )

    #expect(query.isExact)
  }

  @Test(arguments: ["\"unclosed", "tap \"unclosed phrase", "-\"unclosed"])
  func `a quote never closed is refused`(text: String) {
    #expect(throws: UseCaseSearchError.unclosedQuote) {
      try query(text)
    }
  }

  @Test(arguments: ["", "   ", "-zoom", "-zoom -\"to zoom\"", "!!!", "\"\""])
  func `words with nothing to look for are refused`(text: String) {
    #expect(throws: UseCaseSearchError.noWords) {
      try query(text)
    }
  }

  @Test
  func `a phrase alone is enough to look for`() throws {
    #expect(try query("\"double tap\"").phrases == [["double", "tap"]])
  }
}
