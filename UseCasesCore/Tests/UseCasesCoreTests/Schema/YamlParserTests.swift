import Testing
@testable import UseCasesCore

/// YAML is the surface authors type, so the parser is a security boundary as
/// much as a reader: merge keys and custom tags are REFUSED before parsing, and
/// scalars resolve by the YAML 1.2 core schema (`yes` is a string, `017` is
/// seventeen), never by YAML 1.1 rules.
struct YamlParserTests {
  private func parse(_ source: String) -> ParsedYamlResult {
    YamlParser.parseToJSON(source: source, sourcePath: "f.yml")
  }

  @Test
  func `resolves core schema scalars, leaving YAML one point one spellings alone`() throws {
    let result = parse("a: yes\nb: on\nc: 0o17\nd: 017\ne: ~\nf: null\ng: true\nh: 1.5\ni: 0x1f\n")
    let value = try #require(result.value)

    #expect(result.isValid)
    #expect(value["a"] == .string("yes"))
    #expect(value["b"] == .string("on"))
    #expect(value["c"] == .number(15))
    #expect(value["d"] == .number(17))
    #expect(value["e"] == .null)
    #expect(value["f"] == .null)
    #expect(value["g"] == .bool(true))
    #expect(value["h"] == .number(1.5))
    #expect(value["i"] == .number(31))
  }

  @Test
  func `a quoted scalar stays a string`() throws {
    let result = parse("a: \"7\"\nb: ''\nc: \"true\"\nd: \"!Custom\"\n")
    let value = try #require(result.value)

    #expect(value["a"] == .string("7"))
    #expect(value["b"] == .string(""))
    #expect(value["c"] == .string("true"))
    #expect(value["d"] == .string("!Custom"))
  }

  @Test
  func `an empty value is null`() throws {
    let value = try #require(parse("l:\n").value)

    #expect(value["l"] == .null)
  }

  @Test
  func `an empty document parses to null`() {
    let result = parse("")

    #expect(result.isValid)
    #expect(result.value == JSONValue.null)
    #expect(result.diagnostics.isEmpty)
  }

  @Test
  func `parses nested mappings and sequences`() throws {
    let source = "feature:\n  id: auth\n  name: Auth\nuse_cases:\n  - id: auth.login\n"
      + "    tags: [a, b]\n"
      + "  - id: auth.logout\n"
    let value = try #require(parse(source).value)

    #expect(value["feature"]?["id"] == .string("auth"))
    #expect(value["use_cases"]?.arrayValue?.count == 2)
    #expect(value["use_cases"]?.arrayValue?[0]["tags"] == .array([.string("a"), .string("b")]))
  }

  @Test
  func `keeps mapping keys in document order`() throws {
    let value = try #require(parse("zebra: 1\nalpha: 2\nmiddle: 3\n").value)

    #expect(value.objectValue?.keys == ["zebra", "alpha", "middle"])
  }

  @Test
  func `expands an anchor and its alias`() throws {
    let value = try #require(parse("base: &b {a: 1}\nchild: *b\n").value)

    #expect(value["base"]?["a"] == .number(1))
    #expect(value["child"]?["a"] == .number(1))
  }

  @Test
  func `folds a plain multi-line scalar`() throws {
    let value = try #require(parse("a: one\n  two\n").value)

    #expect(value["a"] == .string("one two"))
  }

  @Test
  func `a large integer keeps double precision`() throws {
    let value = try #require(parse("a: 12345678901234567890\n").value)

    #expect(value["a"]?.numberValue == 12_345_678_901_234_567_168 as Double)
  }

  @Test
  func `a signed integer and the infinities resolve as numbers`() throws {
    let value = try #require(parse("a: +5\nb: .inf\nc: -.inf\nd: .nan\n").value)

    #expect(value["a"] == .number(5))
    #expect(value["b"]?.numberValue?.isInfinite == true)
    #expect(value["c"]?.numberValue == -Double.infinity)
    #expect(value["d"]?.numberValue?.isNaN == true)
  }

  @Test
  func `refuses a merge key before parsing`() {
    let result = parse("base: &b\n  a: 1\nchild:\n  << : *b\n")

    #expect(result.isValid == false)
    #expect(result.value == nil)
    #expect(result.diagnostics.map(\.code) == ["yaml.merge_key_rejected"])
    #expect(result.diagnostics.first?.message == "YAML merge keys are not supported.")
    #expect(result.diagnostics.first?.sourcePath == "f.yml")
  }

  @Test(arguments: ["a: !Custom 1\n", "a: [!Foo 1]\n", "!Top\na: 1\n", "a: {b: !Bar 1}\n"])
  func `refuses a custom tag before parsing`(source: String) {
    let result = parse(source)

    #expect(result.isValid == false)
    #expect(result.diagnostics.map(\.code) == ["yaml.custom_tag_rejected"])
    #expect(result.diagnostics.first?.message == "Custom YAML tags are not supported.")
  }

  @Test(arguments: ["a: \"!Custom\"\n", "b: hello! world\n", "c: '!x'\n"])
  func `an exclamation mark inside a value is not a custom tag`(source: String) {
    #expect(parse(source).isValid)
  }

  @Test
  func `refuses a duplicate mapping key with the frozen code and message`() {
    let result = parse("a: 1\na: 2\n")

    #expect(result.isValid == false)
    #expect(result.value == nil)
    #expect(result.diagnostics.map(\.code) == ["yaml.duplicate_key"])
    #expect(result.diagnostics.first?.message == "Map keys must be unique")
  }

  @Test
  func `finds a duplicate key nested inside the document`() {
    let result = parse("feature:\n  id: a\n  id: b\n")

    #expect(result.diagnostics.map(\.code) == ["yaml.duplicate_key"])
  }

  @Test(arguments: ["a: [1, 2\n", "a:\n\tb: 1\n", "a: 1\n---\nb: 2\n", "{\n"])
  func `a broken document reports a parse error against its path`(source: String) {
    let result = parse(source)

    #expect(result.isValid == false)
    #expect(result.value == nil)
    #expect(result.diagnostics.map(\.code) == ["parse_error"])
    #expect(result.diagnostics.first?.sourcePath == "f.yml")
    #expect(result.diagnostics.first?.message.isEmpty == false)
  }

  @Test
  func `a sequence document parses to an array`() throws {
    let value = try #require(parse("- 1\n- two\n- [3]\n").value)

    #expect(value == .array([.number(1), .string("two"), .array([.number(3)])]))
  }

  @Test
  func `a non-string mapping key becomes its scalar spelling`() throws {
    let value = try #require(parse("1: one\ntrue: yes\n").value)

    #expect(value.objectValue?.keys == ["1", "true"])
  }
}
