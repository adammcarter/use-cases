import Testing
@testable import UseCasesCore

struct AuthoredInputErrorTests {
  @Test(arguments: [
    (AuthoredInputError.notAFile(path: "a.yml"), "'a.yml' is not a file"),
    (
      .unreadable(path: "a.yml", reason: "permission denied"),
      "'a.yml' cannot be read: permission denied",
    ),
    (.notUTF8(name: "stdin"), "stdin is not valid UTF-8 text"),
    (
      .limitExceeded(name: "a.json", .values(maximum: 100_000)),
      "a.json: this file holds more than 100,000 values",
    ),
    (
      .json(name: "a.json", .unexpectedEnd),
      "a.json: not valid JSON: the text ends before the document does",
    ),
  ])
  func `each refusal is told in a line that starts with what it is about`(
    error: AuthoredInputError,
    message: String,
  ) {
    #expect(error.message == message)
  }

  @Test
  func `a YAML refusal is told with its file and line`() {
    let error = AuthoredInputError.yaml(
      .duplicateKey(
        YAMLLocation(file: "stdin", line: 3),
        key: "id",
      ),
    )

    #expect(error.message == "stdin:3: duplicate key 'id'")
  }
}
