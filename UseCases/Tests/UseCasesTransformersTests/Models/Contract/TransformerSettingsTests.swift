import Testing
@testable import UseCasesTransformers

struct TransformerSettingsTests {
  private let settings = TransformerSettings(
    values: [
      "name": .string("x"),
      "count": .integer(2),
      "flag": .bool(true),
      "list": .array([.string("a"), .string("b")]),
      "nothing": .null,
    ],
  )

  @Test
  func `settings of the right type are read`() throws {
    #expect(try settings.string("name") == "x")
    #expect(try settings.integer("count") == 2)
    #expect(try settings.boolean("flag") == true)
    #expect(try settings.strings("list") == ["a", "b"])
    #expect(try settings.requiredString("name") == "x")
  }

  @Test
  func `an absent or null setting is nil`() throws {
    #expect(try settings.string("absent") == nil)
    #expect(try settings.string("nothing") == nil)
    #expect(try settings.integer("nothing") == nil)
    #expect(try settings.boolean("absent") == nil)
    #expect(try settings.strings("nothing") == nil)
  }

  @Test
  func `a required setting that is absent is named`() {
    #expect(throws: TransformerFailure.settingMissing("file")) {
      try settings.requiredString("file")
    }
  }

  @Test
  func `a setting of the wrong type is refused with what was expected`() {
    #expect(throws: TransformerFailure.settingInvalid(
      name: "count",
      expected: "text",
    )) {
      try settings.string("count")
    }
    #expect(throws: TransformerFailure.settingInvalid(
      name: "name",
      expected: "a whole number",
    )) {
      try settings.integer("name")
    }
    #expect(throws: TransformerFailure.settingInvalid(
      name: "name",
      expected: "true or false",
    )) {
      try settings.boolean("name")
    }
    #expect(throws: TransformerFailure.settingInvalid(
      name: "name",
      expected: "a list of text",
    )) {
      try settings.strings("name")
    }
  }

  @Test
  func `a list holding anything but text is refused`() {
    let mixed = TransformerSettings(values: ["list": .array([.string("a"), .integer(1)])])

    #expect(throws: TransformerFailure.settingInvalid(
      name: "list",
      expected: "a list of text",
    )) {
      try mixed.strings("list")
    }
  }
}
