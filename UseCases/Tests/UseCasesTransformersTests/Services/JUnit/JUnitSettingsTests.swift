import Testing
@testable import UseCasesTransformers

struct JUnitSettingsTests {
  private func settings(_ values: [String: JSONValue]) throws -> JUnitSettings {
    try JUnitSettings(settings: TransformerSettings(values: values))
  }

  @Test
  func `no settings means file and line, counting from 1`() throws {
    let settings = try settings([:])

    #expect(settings.find == .fileLine)
    #expect(settings.lineBase == 1)
    #expect(settings.base == nil)
    #expect(!settings.usesClassFile)
  }

  @Test(arguments: ["file-line", "file-name", "pattern"])
  func `each way of finding a test is named as the catalogue names it`(name: String) throws {
    let values: [String: JSONValue] = [
      "find": .string(name),
      "files": .string("src/**"),
      "patterns": .array([.string("def {name}")]),
    ]

    #expect(try settings(values).find.rawValue == name)
  }

  @Test
  func `an unknown way of finding tests is refused`() {
    #expect(throws: TransformerFailure.settingInvalid(
      name: "find",
      expected: "file-line, file-name or pattern",
    )) {
      try settings(["find": .string("guess")])
    }
  }

  @Test
  func `a pattern search needs files and patterns`() {
    #expect(throws: TransformerFailure.settingMissing("files")) {
      try settings(["find": .string("pattern"), "patterns": .array([.string("x")])])
    }
    #expect(throws: TransformerFailure.settingMissing("patterns")) {
      try settings(["find": .string("pattern"), "files": .string("**")])
    }
    #expect(throws: TransformerFailure.settingMissing("patterns")) {
      try settings(["find": .string("pattern"), "files": .string("**"), "patterns": .array([])])
    }
  }

  @Test
  func `settings of the wrong type are refused`() {
    #expect(throws: TransformerFailure.settingInvalid(
      name: "line_base",
      expected: "a whole number",
    )) {
      try settings(["line_base": .string("0")])
    }
    #expect(throws: TransformerFailure.settingInvalid(
      name: "class_file",
      expected: "true or false",
    )) {
      try settings(["class_file": .string("yes")])
    }
  }
}
