import Testing
@testable import UseCasesCore

struct AuthoredInputReaderByteOrderMarkTests {
  private let directory: TemporaryDirectory

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func refusal(
    _ source: AuthoredInputSource,
    standardInput: String = "",
  ) -> AuthoredInputError? {
    do {
      _ = try value(
        source,
        standardInput: standardInput,
      )
      return nil
    } catch {
      return error
    }
  }

  private func value(
    _ source: AuthoredInputSource,
    standardInput: String = "",
  ) throws(AuthoredInputError) -> AuthoredValue {
    try AuthoredInputReader(
      standardInput: MockStandardInput(standardInput),
      workingDirectory: directory.url,
    ).read(source).value
  }

  // Mutant: the JSON path does not look, so JSON keeps the mark and YAML drops it.
  @Test(arguments: [
    #"{"title": "\ufeffx"}"#,
    "{\"title\": \"\u{FEFF}x\"}",
    #"{"\ufeffk": 1}"#,
    #"{"when": ["a", "\ufeffb"]}"#,
    #"{"a": {"b": ["\ufeffc"]}}"#,
  ])
  func `JSON text that starts with a byte order mark is refused, as YAML text is`(
    text: String,
  ) throws {
    try directory.write("a.json", text)

    let error = try #require(refusal(.file("a.json")))

    #expect(error == .leadingByteOrderMark(name: "a.json"))
    #expect(error.message.hasPrefix("a.json: text that starts with a byte order mark (U+FEFF)"))
  }

  @Test
  func `the same text on the standard input is refused whether it reads as JSON or YAML`() throws {
    let error = try #require(
      refusal(.standardInput, standardInput: #"{"title": "\ufeffx"}"#),
    )

    #expect(error.message.contains("byte order mark"))
  }

  @Test
  func `YAML text that starts with one is refused from a file and from stdin`() throws {
    try directory.write("a.yml", "title: \"\\uFEFFx\"\n")

    #expect(refusal(.file("a.yml"))?.message.contains("byte order mark") == true)
    #expect(
      refusal(.standardInput, standardInput: "title: \"\\uFEFFx\"\n")?.message
        .contains("byte order mark") == true,
    )
  }

  @Test
  func `a byte order mark inside JSON text is kept`() throws {
    #expect(
      try value(.standardInput, standardInput: #"{"title": "x\ufeffy"}"#)
        == .members(["title": .string("x\u{FEFF}y")]),
    )
  }
}
