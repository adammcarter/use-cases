import Testing
@testable import UseCasesCore

/// Redaction is deliberately narrow: a keyword only matches when an assignment
/// and a value follow it, so legitimate prose survives untouched.
struct RedactorTests {
  @Test(arguments: [
    ("token: abc123", "token=[redacted]"),
    ("token=abc123", "token=[redacted]"),
    ("secret : hunter2", "secret=[redacted]"),
    ("password=p@ssw0rd", "password=[redacted]"),
    ("api_key: 12345", "api_key=[redacted]"),
    ("api-key: 12345", "api-key=[redacted]"),
    ("apikey: 12345", "apikey=[redacted]"),
  ])
  func `redacts an assigned credential keyword`(
    input: String,
    expected: String,
  ) {
    #expect(Redactor.redactSecrets(input) == expected)
  }

  @Test(arguments: [
    "the secret garden",
    "a token of appreciation",
    "password strength matters",
    "tokens are not secrets here",
  ])
  func `leaves prose without an assignment untouched`(input: String) {
    #expect(Redactor.redactSecrets(input) == input)
  }

  @Test
  func `redacts an openai style key`() {
    #expect(Redactor.redactSecrets("use sk-abcdefgh12345 now") == "use sk-[redacted] now")
  }

  @Test
  func `leaves a too short sk prefix alone`() {
    #expect(Redactor.redactSecrets("sk-abc") == "sk-abc")
  }

  @Test(arguments: ["gho", "ghp", "ghr", "ghs", "ghu"])
  func `redacts a github token keeping its prefix`(prefix: String) {
    let token = "\(prefix)_" + String(repeating: "A", count: 24)
    #expect(Redactor.redactSecrets(token) == "\(prefix)_[redacted]")
  }

  @Test
  func `redacts an aws access key id`() {
    #expect(Redactor.redactSecrets("AKIAIOSFODNN7EXAMPLE") == "AKIA[redacted]")
  }

  @Test
  func `redacts every occurrence in one string`() {
    let input = "token: a1 and password: b2"
    #expect(Redactor.redactSecrets(input) == "token=[redacted] and password=[redacted]")
  }

  @Test
  func `leaves an empty string alone`() {
    #expect(Redactor.redactSecrets("").isEmpty)
  }
}
