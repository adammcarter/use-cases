import Testing
@testable import UseCasesCore

struct LikeTextTests {
  private func like(_ json: String) throws -> LikeText {
    guard case let .object(members) = try AuthoredValue.json(json) else {
      throw LoadFailure(message: "not an object")
    }

    return LikeText(members)
  }

  @Test
  func `the title, intent, scenarios and out of scope are the words, each once`() throws {
    let text = try like(
      """
      {"id": "app.a.b", "title": "Tap a photo", "intent": "Photo taps.",
       "scenarios": [{"id": "s", "given": ["A photo"], "when": ["Tap it"], "then": ["It zooms"]}],
       "out_of_scope": ["Video"], "description": "ignored words"}
      """,
    )

    #expect(text.words == [
      "tap", "a", "photo", "taps", "it", "zooms", "video",
    ])
    #expect(text.identifier == "app.a.b")
  }

  @Test
  func `a field of the wrong type is skipped, not refused`() throws {
    let text = try like(
      #"{"title": 5, "intent": ["x"], "scenarios": "no", "out_of_scope": [1, "Keep"], "id": 3}"#,
    )

    #expect(text.words == ["keep"])
    #expect(text.identifier == nil)
  }

  @Test
  func `an empty use case has no words and no id`() throws {
    let text = try like("{}")

    #expect(text.words.isEmpty)
    #expect(text.identifier == nil)
  }
}
