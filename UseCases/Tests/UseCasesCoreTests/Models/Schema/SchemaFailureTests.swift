import Testing
@testable import UseCasesCore

struct SchemaFailureTests {
  @Test
  func `a failure at the document has only its message`() {
    let failure = SchemaFailure(
      path: [],
      keyword: .type,
      message: "42 is not of type 'string'",
    )

    #expect(failure.pathText.isEmpty)
    #expect(failure.description == "42 is not of type 'string'")
  }

  @Test
  func `a failure deeper down says where it is and which keyword failed`() {
    let failure = SchemaFailure(
      path: [.key("groups"), .key("g"), .key("include"), .key("globs"), .index(0)],
      keyword: .pattern,
      message: "'app.log*' is not allowed",
    )

    #expect(failure.pathText == "groups/g/include/globs/0")
    #expect(failure.keyword == .pattern)
    #expect(failure.description == "'app.log*' is not allowed at groups/g/include/globs/0")
  }

  @Test
  func `failures sort by path with indexes in numeric order, then keyword, then message`() {
    let failures = [
      SchemaFailure(path: [.key("b")], keyword: .type, message: "z"),
      SchemaFailure(path: [.key("a"), .index(10)], keyword: .type, message: "z"),
      SchemaFailure(path: [.key("a"), .index(2)], keyword: .pattern, message: "a"),
      SchemaFailure(path: [.key("a"), .index(2)], keyword: .type, message: "b"),
      SchemaFailure(path: [.key("a"), .index(2)], keyword: .type, message: "a"),
      SchemaFailure(path: [.key("a")], keyword: .type, message: "z"),
      SchemaFailure(path: [], keyword: .required, message: "z"),
      SchemaFailure(path: [], keyword: .minimum, message: "z"),
    ]

    #expect(failures.sorted().map(\.description) == [
      "z",
      "z",
      "z at a",
      "a at a/2",
      "b at a/2",
      "a at a/2",
      "z at a/10",
      "z at b",
    ])
    #expect(failures.sorted().map(\.keyword) == [
      .minimum, .required, .type, .type, .type, .pattern, .type, .type,
    ])
  }

  @Test
  func `keywords order the way the evaluator checks them`() {
    #expect(SchemaKeyword.allCases.sorted() == SchemaKeyword.allCases)
    #expect(SchemaKeyword.type < SchemaKeyword.const)
    #expect(SchemaKeyword.required < SchemaKeyword.additionalProperties)
    #expect(SchemaKeyword.not < SchemaKeyword.falseSchema)
  }

  @Test(arguments: [
    (SchemaPathStep.index(2), SchemaPathStep.index(10)),
    (.index(0), .key("")),
    (.key("a"), .key("b")),
    (.key("B"), .key("a")),
    (.key("e\u{301}"), .key("\u{E9}")),
  ])
  func `a step orders before the next`(
    first: SchemaPathStep,
    second: SchemaPathStep,
  ) {
    #expect(first < second)
    #expect(!(second < first))
  }

  @Test
  func `keys that are canonically equivalent are different steps`() {
    let composed = SchemaPathStep.key("\u{E9}")
    let decomposed = SchemaPathStep.key("e\u{301}")
    let kelvin = SchemaPathStep.key("\u{212A}")

    #expect(composed != decomposed)
    #expect(kelvin != .key("K"))
    #expect(Set([composed, decomposed, kelvin, .key("K")]).count == 4)
  }

  @Test
  func `failures with messages that are canonically equivalent are different failures`() {
    let composed = SchemaFailure(path: [], keyword: .type, message: "\u{E9}")
    let decomposed = SchemaFailure(path: [], keyword: .type, message: "e\u{301}")

    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
  }
}
