import Testing
@testable import UseCasesCore

struct YAMLEmitterTests {
  private let emitter = YAMLEmitter(
    layout: YAMLLayout(
      width: 30,
      column: 0,
    ),
  )

  private func lines(_ value: StoreJSONValue) -> [String] {
    emitter.lines(of: value)
  }

  @Test
  func `members are written one per line, in the order given`() {
    let value = StoreJSONValue.members([
      "id": .string("a.b.c"),
      "title": .string("Log in"),
      "count": .integer(3),
      "ready": .boolean(true),
      "ratio": .number(1.5),
      "nothing": .null,
    ])

    #expect(lines(value) == [
      "id: a.b.c", "title: Log in", "count: 3", "ready: true", "ratio: 1.5", "nothing: null",
    ])
  }

  @Test
  func `a list that fits goes on its key's line, with no space inside the brackets`() {
    let value = StoreJSONValue.members(["when": .strings(["x", "z"])])

    #expect(lines(value) == ["when: [x, z]"])
  }

  @Test
  func `a mapping that fits goes on its key's line, with a space inside the braces`() {
    let value = StoreJSONValue.members([
      "type": .members(["kind": .string("unit")]),
    ])

    #expect(lines(value) == ["type: { kind: unit }"])
  }

  @Test
  func `a list is a block under its key when its line would pass the width`() {
    // "steps: [" and "]" are 9 characters: 21 more make 30, which is the width, and 22 pass it.
    let atWidth = StoreJSONValue.members(["steps": .strings([String(repeating: "a", count: 21)])])
    let pastWidth = StoreJSONValue.members(["steps": .strings([String(repeating: "a", count: 22)])])

    #expect(lines(atWidth) == ["steps: [\(String(repeating: "a", count: 21))]"])
    #expect(lines(pastWidth) == ["steps:", "  - \(String(repeating: "a", count: 22))"])
  }

  @Test
  func `a line is measured from the column the use case sits at in its file`() {
    let inFile = YAMLEmitter(
      layout: YAMLLayout(
        width: 30,
        column: 4,
      ),
    )
    let value = StoreJSONValue.members(["steps": .strings([String(repeating: "a", count: 17)])])

    // "steps: [" + 17 + "]" is 26 characters, and four more of margin make it 30.
    #expect(inFile.lines(of: value) == ["steps: [\(String(repeating: "a", count: 17))]"])
    #expect(
      inFile.lines(of: .members(["steps": .strings([String(repeating: "a", count: 18)])])) == [
        "steps:", "  - \(String(repeating: "a", count: 18))",
      ],
    )
  }

  @Test
  func `characters are counted as scalars, not bytes`() {
    let value = StoreJSONValue.members(["when": .strings([String(repeating: "😀", count: 20)])])

    #expect(lines(value) == ["when: [\(String(repeating: "😀", count: 20))]"])
  }

  @Test
  func `a text is never wrapped, however long`() {
    let long = String(repeating: "word ", count: 40) + "end"

    #expect(lines(.members(["intent": .string(long)])) == ["intent: \(long)"])
  }

  @Test
  func `a list that does not fit is indented under its key`() {
    let value = StoreJSONValue.members([
      "steps": .strings(["first step of the procedure", "second step of the procedure"]),
      "after": .string("x"),
    ])

    #expect(lines(value) == [
      "steps:",
      "  - first step of the procedure",
      "  - second step of the procedure",
      "after: x",
    ])
  }

  @Test
  func `a list item that is a mapping is a block, its first member beside the dash`() {
    let value = StoreJSONValue.members([
      "resources": .array([
        .members(["kind": .string("file"), "path": .string("a.json")]),
        .members(["kind": .string("glob"), "pattern": .string("*.json")]),
      ]),
    ])

    #expect(lines(value) == [
      "resources:",
      "  - kind: file",
      "    path: a.json",
      "  - kind: glob",
      "    pattern: \"*.json\"",
    ])
  }

  @Test
  func `a mapping with a collection in it is a block, and the collection takes its own line`() {
    let value = StoreJSONValue.members([
      "locator": .members([
        "file": .string("src/login.py"),
        "start": .members(["line": .integer(40)]),
      ]),
    ])

    #expect(lines(value) == [
      "locator:",
      "  file: src/login.py",
      "  start: { line: 40 }",
    ])
  }

  @Test
  func `a key YAML 1_1 reads differently is quoted`() {
    let value = StoreJSONValue.members([
      "approved": .members([
        "by": .string("Sam"),
        "on": .string("2026-10-11"),
      ]),
    ])

    #expect(lines(value) == [
      "approved:",
      "  by: Sam",
      "  \"on\": \"2026-10-11\"",
    ])
  }

  @Test
  func `an empty list and an empty mapping are written empty`() {
    let value = StoreJSONValue.members([
      "list": .array([]),
      "mapping": .object([]),
    ])

    #expect(lines(value) == ["list: []", "mapping: {}"])
  }

  @Test
  func `items of a list that is itself a list are written under a dash of their own`() {
    let value = StoreJSONValue.members([
      "grid": .array([
        .strings(["a", "b"]),
        .strings(["c", "d"]),
      ]),
    ])

    #expect(lines(value) == ["grid:", "  - [a, b]", "  - [c, d]"])
  }

  @Test
  func `a value that is not a mapping is written alone`() {
    #expect(lines(.string("x")) == ["x"])
    #expect(lines(.array([])) == ["[]"])
    #expect(lines(.strings(["a", "b"])) == ["- a", "- b"])
  }

  // MARK: - Text of several lines

  // Mutant: a multi-line text written in quotes with `\n` instead of as a block.
  @Test
  func `text of several lines is a literal block under its key`() {
    let value = StoreJSONValue.members([
      "intent": .string("First line.\nSecond line."),
      "after": .string("x"),
    ])

    #expect(lines(value) == ["intent: |-", "  First line.", "  Second line.", "after: x"])
  }

  @Test(arguments: [
    ("a\nb", "|-"),
    ("a\nb\n", "|"),
    ("a\nb\n\n", "|+"),
    (" a\nb", "|2-"),
  ])
  func `the header of the block says how the text ends and starts`(
    text: String,
    header: String,
  ) {
    #expect(lines(.members(["k": .string(text)])).first == "k: " + header)
  }

  @Test
  func `the lines of a block sit two spaces in from their key, however deep it is`() {
    let value = StoreJSONValue.members([
      "outer": .members(["inner": .string("a\nb")]),
    ])

    #expect(lines(value) == ["outer:", "  inner: |-", "    a", "    b"])
  }

  // Mutant: a list with a multi-line item kept on one line.
  @Test
  func `a list with a text of several lines is a block list, the text a block under its dash`() {
    let value = StoreJSONValue.members([
      "when": .strings(["short", "first\nsecond", "last"]),
    ])

    #expect(lines(value) == [
      "when:", "  - short", "  - |-", "    first", "    second", "  - last",
    ])
  }

  @Test
  func `a text of several lines in the first member of a list item is a block beside the dash`() {
    let value = StoreJSONValue.members([
      "steps": .array([
        .members(["text": .string("a\nb"), "count": .integer(1)]),
      ]),
    ])

    #expect(lines(value) == ["steps:", "  - text: |-", "      a", "      b", "    count: 1"])
  }

  @Test
  func `a blank line in a block stays empty`() {
    let value = StoreJSONValue.members(["k": .string("a\n\nb\n\n"), "j": .integer(1)])

    #expect(lines(value) == ["k: |+", "  a", "", "  b", "", "j: 1"])
  }

  @Test
  func `text a block cannot hold exactly is quoted, and a list of it is a block list`() {
    #expect(lines(.members(["k": .string("a\r\nb")])) == ["k: \"a\\r\\nb\""])
    #expect(lines(.members(["k": .strings(["a\r\nb"])])) == ["k:", "  - \"a\\r\\nb\""])
  }

  @Test
  func `a key is never a block`() {
    #expect(lines(.members(["a\nb": .integer(1)])) == ["\"a\\nb\": 1"])
  }

  @Test(arguments: [
    StoreJSONValue.null,
    .boolean(false),
    .integer(-7),
    .number(0.25),
  ])
  func `numbers, booleans and null are written bare`(value: StoreJSONValue) {
    let written = lines(.members(["key": value]))

    #expect(written.count == 1)
    #expect(!(written.first?.contains("\"") ?? true))
  }

  @Test
  func `a number JSON cannot hold is written as null`() {
    #expect(lines(.members(["key": .number(.infinity)])) == ["key: null"])
  }
}
