import Testing
@testable import UseCasesCore

struct StrictYAMLReaderDocumentTests {
  private let reader = StrictYAMLReader()

  @Test(arguments: ["", "\n", "   \n\n", "# only a comment\n", "\u{FEFF}", "\u{FEFF}\n# note\n"])
  func `a file with no content reads as an empty object`(text: String) {
    #expect(reader.attempt(text).success == .object([]))
  }

  @Test
  func `a byte order mark at the start is ignored`() {
    let result = reader.attempt("\u{FEFF}title: Dark mode\n")

    #expect(result.success == .members(["title": .string("Dark mode")]))
  }

  @Test
  func `a byte order mark does not shift the line or column of a refusal`() {
    let tagged = reader.attempt("\u{FEFF}a: !!str x\n")
    let cut = reader.attempt("\u{FEFF}title: Dark mode # note\n")

    #expect(tagged.failure == .tagged(YAMLLocation(file: "use-cases/a.yml", line: 1)))
    #expect(cut.failure?.line == 1)
  }

  @Test
  func `a byte order mark anywhere else is not ignored`() {
    let result = reader.attempt("a: 1\n\u{FEFF}b: 2\n")

    #expect(result.success == nil)
  }

  @Test(arguments: [
    ("a: 1\n---\nb: 2\n", 2),
    ("---\na: 1\n---\nb: 2\n", 3),
    ("a: 1\n...\n---\nb: 2\n", 3),
    ("a: 1\n---\n", 2),
    ("---\n---\n", 2),
  ])
  func `a second document is refused as breaking the single document rule`(
    text: String,
    line: Int,
  ) throws {
    let error = try #require(reader.attempt(text).failure)

    #expect(error == .multipleDocuments(YAMLLocation(file: "use-cases/a.yml", line: line)))
    #expect(error.message.contains("single document"))
  }

  @Test(arguments: [
    ("a: !!str x\n", 1),
    ("a: !!seq [x]\n", 1),
    ("a: [!note x]\n", 1),
    ("a: !x\n  b: 1\n", 1),
    ("a: &anchor !!str x\n", 1),
    ("!!map {a: 1}\n", 1),
    ("a: ! x\n", 1),
    ("a: !!str \"x\"\n", 1),
    ("a: !!str 'x'\n", 1),
    ("!!str a: 1\n", 1),
    ("x: 1\ny: !!null\n", 2),
    ("x:\n  - 1\n  - !!int 2\n", 3),
    ("a: &x\n  !!str y\n", 2),
    ("a: !<tag:yaml.org,2002:str> x\n", 1),
    ("a: !!binary |\n  aGk=\n", 1),
  ])
  func `a tag is refused wherever it is written`(
    text: String,
    line: Int,
  ) throws {
    let error = try #require(reader.attempt(text).failure)

    #expect(error == .tagged(YAMLLocation(file: "use-cases/a.yml", line: line)))
    #expect(error.message.contains("tag"))
  }

  @Test(arguments: [
    ("a: &x # c\n  !!str 42", 2),
    ("a: &x\n  # c\n  !!str 42", 3),
    ("- &x # c\n  !t v", 2),
    ("a: &x # c\n  # d\n\n  # e\n  !!str 42\n", 5),
    ("a: &x   # c\r\n  !!str 42\r\n", 2),
  ])
  func `a tag after an anchor and comments is still refused`(
    text: String,
    line: Int,
  ) {
    for kind in [AuthoredFileKind.settings, .useCase] {
      let error = reader.attempt(text, kind: kind).failure

      #expect(error == .tagged(YAMLLocation(file: "use-cases/a.yml", line: line)))
    }
  }

  @Test(arguments: [
    "a: [!!str x]\n", "a: {k: !!str v}\n", "a: !!set {x}\n", "a: !!omap [x: 1]\n",
  ])
  func `a tag is refused in settings files too`(text: String) {
    #expect(reader.attempt(text, kind: .settings).failure != nil)
  }

  @Test(arguments: [
    ("a: &x 1\nb: *x\n", AuthoredValue.members(["a": .integer(1), "b": .integer(1)])),
    ("a: &x hello\nb: *x\n", .members(["a": .string("hello"), "b": .string("hello")])),
    (
      "a: &x [1, 2]\nb: *x\n",
      .members(["a": .array([.integer(1), .integer(2)]), "b": .array([.integer(1), .integer(2)])]),
    ),
    (
      "a: &x {k: v}\nb: *x\n",
      .members(["a": .members(["k": .string("v")]), "b": .members(["k": .string("v")])]),
    ),
    ("a: &x\n  - 1\nb: *x\n", .members(["a": .array([.integer(1)]), "b": .array([.integer(1)])])),
    ("a: &x \"1\"\nb: *x\n", .members(["a": .string("1"), "b": .string("1")])),
    ("&root\na: 1\n", .members(["a": .integer(1)])),
    (
      "when: &both [x]\nthen: *both\n",
      .members(["when": .array([.string("x")]), "then": .array([.string("x")])]),
    ),
  ])
  func `anchors and aliases are authoring conveniences that read as plain values`(
    text: String,
    expected: AuthoredValue,
  ) {
    #expect(reader.attempt(text).success == expected)
  }

  @Test(arguments: [
    "a: &a [*a]\n",
    "&a {b: *a}\n",
    "a: *missing\n",
    "&a\n- *a\n",
    "- *a\n- &a x\n"
  ])
  func `a recursive structure or an alias to nothing is refused`(text: String) throws {
    let error = try #require(reader.attempt(text).failure)

    guard case .undefinedAlias = error else {
      Issue.record("\(text) was refused as \(error), not as an undefined alias")
      return
    }

    #expect(error.message.contains("alias"))
  }

  @Test(arguments: [
    ("title: a\ntitle: b\n", 1, "title"),
    ("a: 1\nb: 2\na: 3\n", 1, "a"),
    ("x:\n  y: 1\n  y: 2\n", 2, "y"),
    ("{a: 1, a: 2}\n", 1, "a"),
    ("- title: a\n  title: b\n", 1, "title"),
    ("\"title\": a\ntitle: b\n", 1, "title"),
    ("'a': 1\n\"a\": 2\n", 1, "a"),
    ("p:\n  q: 1\n  r: 2\n  q: 3\n", 2, "q"),
  ])
  func `a duplicate key is refused naming the key and the line it was first written on`(
    text: String,
    line: Int,
    key: String,
  ) throws {
    let error = try #require(reader.attempt(text).failure)

    #expect(error == .duplicateKey(YAMLLocation(file: "use-cases/a.yml", line: line), key: key))
    #expect(error.message.contains("duplicate key '\(key)'"))
  }

  @Test(arguments: [
    "- a: 1\n- a: 2\n", "a: {a: 1}\n", "a: 1\nA: 2\n", "a: 1\n\"a \": 2\n", "a: [{k: 1}, {k: 2}]\n",
  ])
  func `the same key in different mappings is not a duplicate`(text: String) {
    #expect(reader.attempt(text).success != nil)
  }

  @Test(arguments: ["? [a, b]\n: 1\n", "? {a: 1}\n: 2\n", "[a]: 1\n", "{a: 1}: 2\n"])
  func `a key that is a list or a mapping is refused`(text: String) throws {
    let error = try #require(reader.attempt(text).failure)

    guard case .unusableKey = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }

    #expect(error.message.contains("key"))
  }

  @Test(arguments: [
    ("\"1\": x\n", "1"), ("\"true\": x\n", "true"), ("\"~\": x\n", "~"),
    ("\"on\": x\n", "on"), ("'a b': x\n", "a b"), ("'1.5': x\n", "1.5"),
    ("\"\": x\n", ""), ("\"1:30\": x\n", "1:30"), ("a b: x\n", "a b"), ("a1: x\n", "a1"),
  ])
  func `a key reads as the text it was written with`(
    text: String,
    key: String,
  ) {
    #expect(reader.attempt(text).success == .members([key: .string("x")]))
  }

  @Test
  func `an object keeps its members in the order they were written`() {
    let result = reader.attempt("z: 1\na: 2\nm: 3\nb: {y: 1, c: 2, x: 3}\n")

    #expect(result.success == .members([
      "z": .integer(1),
      "a": .integer(2),
      "m": .integer(3),
      "b": .members(["y": .integer(1), "c": .integer(2), "x": .integer(3)]),
    ]))
  }

  @Test
  func `a nested document reads as plain values`() {
    let text = """
    prefix: dark
    use_cases:
      - id: toggle
        title: "No"
        count: 3
        ratio: 0.5
        done: false
        parent: ~
        tags: [a, b]
        steps:
          - Check it.
          - |
            Twice.
            Then once more.
        nested: {k: v, list: [1, 2.5, x]}
    """

    let result = reader.attempt(text)

    #expect(result.success == .members([
      "prefix": .string("dark"),
      "use_cases": .array([
        .members([
          "id": .string("toggle"),
          "title": .string("No"),
          "count": .integer(3),
          "ratio": .number(0.5),
          "done": .boolean(false),
          "parent": .null,
          "tags": .array([.string("a"), .string("b")]),
          "steps": .array([
            .string("Check it."),
            .string("Twice.\nThen once more.\n"),
          ]),
          "nested": .members([
            "k": .string("v"),
            "list": .array([.integer(1), .number(2.5), .string("x")]),
          ]),
        ]),
      ]),
    ]))
  }

  @Test
  func `a document may be a bare value`() {
    #expect(reader.attempt("42\n").success == .integer(42))
    #expect(reader.attempt("[a, 1]\n").success == .array([.string("a"), .integer(1)]))
    #expect(reader.attempt("- a\n- b\n").success == .array([.string("a"), .string("b")]))
  }

  @Test(arguments: [
    "a: [1, 2\n", "a: b: c\n", "key: 'unterminated\n", "{a: 1\n", "a: 1\n b: 2\n", "a: \"\\q\"\n",
    "a:\n\t- x\n", "- a\nb: 1\n", "\u{1}\n",
  ])
  func `text that is not YAML is refused with its line`(text: String) throws {
    let error = try #require(reader.attempt(text).failure)

    guard case .malformed = error else {
      Issue.record("\(text) was refused as \(error)")
      return
    }

    #expect(error.line >= 1)
    #expect(error.message.hasPrefix("use-cases/a.yml:\(error.line): "))
  }

  @Test
  func `every message starts with the file name the caller gave and the line`() throws {
    let error = try #require(
      reader.attempt(
        "ok: 1\nbad: !!str x\n",
        file: "use-cases.yml",
      ).failure,
    )

    #expect(error.message.hasPrefix("use-cases.yml:2: "))
  }

  @Test
  func `reading is repeatable`() {
    let text = "a: [1, on]\n"

    #expect(reader.attempt(text) == reader.attempt(text))
  }
}
