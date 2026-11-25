import Foundation
import Testing
@testable import UseCasesCore

struct AuthoredInputReaderTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func reader(
    standardInput: String = "",
    limits: YAMLReadingLimits = .standard,
  ) -> AuthoredInputReader {
    AuthoredInputReader(
      standardInput: MockStandardInput(standardInput),
      limits: limits,
      workingDirectory: directory.url,
    )
  }

  /// The error the reader refuses the input with.
  private func refusal(
    _ source: AuthoredInputSource,
    standardInput: String = "",
    limits: YAMLReadingLimits = .standard,
  ) -> AuthoredInputError? {
    do {
      _ = try reader(
        standardInput: standardInput,
        limits: limits,
      ).read(source)
      return nil
    } catch {
      return error
    }
  }

  private func value(
    _ source: AuthoredInputSource,
    standardInput: String = "",
  ) throws -> AuthoredValue {
    try reader(standardInput: standardInput).read(source).value
  }

  private static let useCase: AuthoredValue = .members([
    "id": .string("app.dark.contrast"),
    "title": .string("High contrast"),
  ])

  // MARK: The input

  @Test
  func `a YAML file is read, and called by the path it was named by`() throws {
    try directory.write("new.yml", "id: app.dark.contrast\ntitle: High contrast\n")

    let input = try reader().read(.file("new.yml"))

    #expect(input.name == "new.yml")
    #expect(input.value == Self.useCase)
  }

  @Test
  func `a JSON file is read`() throws {
    try directory.write("new.json", #"{"id": "app.dark.contrast", "title": "High contrast"}"#)

    #expect(try value(.file("new.json")) == Self.useCase)
  }

  @Test
  func `the standard input is called stdin, and is read as YAML`() throws {
    let input = try reader(standardInput: "id: app.dark.contrast\ntitle: High contrast\n")
      .read(.standardInput)

    #expect(input.name == "stdin")
    #expect(input.value == Self.useCase)
  }

  @Test
  func `the standard input is read as JSON when it is JSON`() throws {
    let found = try value(
      .standardInput,
      standardInput: #"{"id": "app.dark.contrast", "title": "High contrast"}"#,
    )

    #expect(found == Self.useCase)
  }

  @Test
  func `a JSON array is read as a list`() throws {
    #expect(try value(.standardInput, standardInput: #"["a", 1]"#) == .array([
      .string("a"),
      .integer(1),
    ]))
  }

  @Test
  func `flow YAML on the standard input is YAML`() throws {
    let found = try value(
      .standardInput,
      standardInput: "{ id: app.dark.contrast, title: High contrast }",
    )

    #expect(found == Self.useCase)
  }

  @Test
  func `a byte order mark in front is ignored in YAML and in JSON`() throws {
    #expect(
      try value(.standardInput, standardInput: "\u{FEFF}id: app.dark.contrast\n")
        == .members(["id": .string("app.dark.contrast")]),
    )
    #expect(
      try value(.standardInput, standardInput: "\u{FEFF}{\"id\": \"a\"}")
        == .members(["id": .string("a")]),
    )
  }

  @Test
  func `JSON that escapes a character outside the first plane as a pair is read`() throws {
    try directory.write("emoji.json", #"{"title": "Done 😀"}"#)

    #expect(try value(.file("emoji.json")) == .members(["title": .string("Done 😀")]))
    #expect(
      try value(.standardInput, standardInput: #"{"title": "Done 😀"}"#)
        == .members(["title": .string("Done 😀")]),
    )
  }

  @Test
  func `an empty file is an empty mapping, as it is in a use case file`() throws {
    try directory.write("empty.yml", "")

    #expect(try value(.file("empty.yml")) == .object([]))
  }

  // MARK: The same rules as an authored file

  @Test(arguments: [
    ("id: a\nid: b\n", "duplicate key 'id'"),
    ("title: High contrast   # for low vision\n", "is followed by '# for low vision'"),
    ("title: No\n", "quote it"),
    ("title: 1e3\n", "quote it"),
    ("title: !note x\n", "a tag"),
    ("title: a\n---\ntitle: b\n", "a single document"),
    ("base: &a {x: 1}\nuse: {<<: *a}\n", "quote it"),
    ("title: [unclosed\n", "not valid YAML"),
  ])
  func `YAML is held to the rules of an authored file`(
    text: String,
    message: String,
  ) throws {
    let error = try #require(refusal(.standardInput, standardInput: text))

    guard case .yaml = error else {
      Issue.record("not a YAML refusal: \(error)")
      return
    }

    #expect(error.message.contains(message))
    #expect(error.message.hasPrefix("stdin:"))
  }

  @Test
  func `a refusal names the file and the line`() throws {
    try directory.write("new.yml", "id: app.dark.contrast\ntitle: High contrast   # note\n")

    let error = try #require(refusal(.file("new.yml")))

    #expect(error.message.hasPrefix("new.yml:2: 'High contrast' is followed by '# note'"))
    #expect(error.message.contains("quote the whole text"))
  }

  @Test
  func `text is quoted, and a note on its own line is fine`() throws {
    let found = try value(
      .standardInput,
      standardInput: "# a note\ntitle: \"No\"\nafter: \"High contrast\"  # fine after quotes\n",
    )

    #expect(found == .members([
      "title": .string("No"),
      "after": .string("High contrast"),
    ]))
  }

  @Test
  func `JSON is held to its own rules: no duplicate key`() throws {
    try directory.write("dup.json", #"{"id": "a", "id": "b"}"#)

    let error = try #require(refusal(.file("dup.json")))

    #expect(error == .json(name: "dup.json", .duplicateKey("id", offset: 12)))
    #expect(error.message.hasPrefix("dup.json: not valid JSON: duplicate key"))
  }

  @Test
  func `JSON on the standard input with a duplicate key is refused`() throws {
    let error = try #require(refusal(.standardInput, standardInput: #"{"id": "a", "id": "b"}"#))

    #expect(error.message.contains("duplicate key 'id'"))
  }

  @Test
  func `a number JSON writes as 1e3 is a number, not a text YAML 1_1 reads differently`() throws {
    try directory.write("a.json", #"{"limit": 1e3}"#)
    try directory.write("a.yml", "limit: 1e3\n")

    #expect(try value(.file("a.json")) == .members(["limit": .number(1000)]))
    #expect(refusal(.file("a.yml")) != nil)
  }

  // MARK: Which format

  @Test(arguments: ["a.json", "A.JSON"])
  func `a file named json is JSON, whatever it holds`(name: String) throws {
    try directory.write(name, "id: a\n")

    let error = try #require(refusal(.file(name)))

    guard case .json = error else {
      Issue.record("not a JSON refusal: \(error)")
      return
    }
  }

  @Test(arguments: ["a.yml", "a.yaml"])
  func `a file named yml or yaml is YAML`(name: String) throws {
    try directory.write(name, #"{"id": "a"}"#)

    #expect(try value(.file(name)) == .members(["id": .string("a")]))
    try directory.write(name, "{\"id\": 1e3}")
    #expect(refusal(.file(name)) != nil)
  }

  @Test
  func `a file with any other name is JSON when it reads as JSON, and YAML otherwise`() throws {
    try directory.write("a.txt", #"{"limit": 1e3}"#)
    try directory.write("b.txt", "limit: 5\n")

    #expect(try value(.file("a.txt")) == .members(["limit": .number(1000)]))
    #expect(try value(.file("b.txt")) == .members(["limit": .integer(5)]))
  }

  // MARK: Limits

  @Test
  func `JSON nested deeper than 64 levels is refused before it is parsed`() throws {
    let deep = String(repeating: "[", count: 65) + String(repeating: "]", count: 65)
    try directory.write("deep.json", deep)

    let error = try #require(refusal(.file("deep.json")))

    #expect(error == .limitExceeded(name: "deep.json", .nesting(maximum: 64)))
    #expect(error.message == "deep.json: this is nested deeper than 64 levels")
  }

  @Test
  func `JSON nested 64 levels deep is read`() throws {
    let deep = String(repeating: "[", count: 64) + String(repeating: "]", count: 64)
    try directory.write("deep.json", deep)

    #expect(refusal(.file("deep.json")) == nil)
  }

  @Test
  func `deep nesting on the standard input is refused whether it reads as JSON or YAML`() throws {
    let deep = String(repeating: "[", count: 65) + String(repeating: "]", count: 65)

    let error = try #require(refusal(.standardInput, standardInput: deep))

    #expect(error.message.contains("nested deeper than 64 levels"))
  }

  @Test
  func `brackets inside a JSON string are not nesting`() throws {
    let brackets = String(repeating: "[", count: 200)
    let text = "{\"title\": \"" + brackets + "\"}"

    #expect(try value(.standardInput, standardInput: text) == .members([
      "title": .string(brackets),
    ]))
  }

  @Test
  func `JSON that holds more values than the limit is refused`() throws {
    let limits = YAMLReadingLimits(
      nesting: 64,
      values: 5,
    )
    try directory.write("many.json", "[1, 2, 3, 4, 5]")
    try directory.write("few.json", "[1, 2, 3, 4]")

    #expect(
      refusal(.file("many.json"), limits: limits)
        == .limitExceeded(name: "many.json", .values(maximum: 5)),
    )
    #expect(refusal(.file("few.json"), limits: limits) == nil)
  }

  // MARK: The file

  @Test(arguments: ["missing.yml", "folder", "nested/missing.yml"])
  func `a path that is no file is refused as not a file`(path: String) throws {
    try directory.makeDirectory("folder")

    let error = try #require(refusal(.file(path)))

    #expect(error == .notAFile(path: path))
    #expect(error.message == "'\(path)' is not a file")
  }

  @Test
  func `a pipe is refused without being opened`() throws {
    try directory.makeFIFO("pipe.yml")

    #expect(refusal(.file("pipe.yml")) == .notAFile(path: "pipe.yml"))
  }

  @Test
  func `a link to a file is the file, and a link to nothing is not a file`() throws {
    try directory.write("real.yml", "id: a\n")
    try directory.symlink("link.yml", to: "real.yml")
    try directory.symlink("dangling.yml", to: "nowhere.yml")

    #expect(try value(.file("link.yml")) == .members(["id": .string("a")]))
    #expect(refusal(.file("dangling.yml")) == .notAFile(path: "dangling.yml"))
  }

  @Test
  func `a relative path is read from the working directory and an absolute one as it is`() throws {
    try directory.write("sub/new.yml", "id: a\n")

    #expect(try value(.file("sub/new.yml")) == .members(["id": .string("a")]))
    #expect(
      try value(.file(directory.location(of: "sub/new.yml").path))
        == .members(["id": .string("a")]),
    )
  }

  @Test
  func `a file that is not UTF-8 is refused, named by its path`() throws {
    try directory.write("latin.yml", bytes: [0x74, 0x3A, 0x20, 0xE9, 0x0A])

    #expect(refusal(.file("latin.yml")) == .notUTF8(name: "latin.yml"))
  }

  @Test
  func `a file that cannot be read says why`() {
    let reader = AuthoredInputReader(
      fileSystem: UnreadableFileSystem(),
      standardInput: MockStandardInput(""),
      workingDirectory: directory.url,
    )

    do {
      _ = try reader.read(.file("locked.yml"))
      Issue.record("read")
    } catch {
      #expect(error == .unreadable(path: "locked.yml", reason: "permission denied"))
      #expect(error.message == "'locked.yml' cannot be read: permission denied")
    }
  }

  @Test
  func `a standard input that is not text is refused`() {
    let reader = AuthoredInputReader(
      standardInput: MockStandardInput(failing: .notUTF8(name: "stdin")),
      workingDirectory: directory.url,
    )

    do {
      _ = try reader.read(.standardInput)
      Issue.record("read")
    } catch {
      #expect(error.message == "stdin is not valid UTF-8 text")
    }
  }
}
