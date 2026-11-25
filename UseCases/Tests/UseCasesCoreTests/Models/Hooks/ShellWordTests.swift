import Foundation
import Testing
@testable import UseCasesCore

struct ShellWordTests {
  /// Text a shell must hand back exactly: quotes, backticks, `$()`, newlines, and each of them
  /// followed by a combining mark, which Swift joins into one character with it.
  private static let texts = [
    "plain", "a b", "it's", "'", "''", "`", "\"q\"", "back\\slash", "$HOME", "$(touch PWNED)",
    "a\nb", "e\u{301}", "😀 ok", "tab\there", "-dash", "~", "a;b&c|d", "*?[x]",
    "`\u{301};touch PWNED;`\u{301}", "'\u{301}", "x'\u{301}y'\u{301}", "$\u{301}(id)",
    "\"\u{301}", "\\\u{301}", "/work/`\u{301};touch PWNED;`\u{301}/use-cases",
  ]

  private func output(of script: String) async throws -> String {
    let fixture = try ProcessFixture()
    let run = try await fixture.supervisor().run(fixture.request(script))

    return run.console.text
  }

  // MARK: - Writing

  @Test
  func `a word of safe characters is bare, and nothing is the empty word`() {
    #expect(ShellWord.quoting("/opt/use-cases/bin/use-cases") == "/opt/use-cases/bin/use-cases")
    #expect(ShellWord.quoting("") == "''")
  }

  @Test(arguments: [
    ("a b", "'a b'"),
    ("it's", "'it'\\''s'"),
    // A quote with a combining mark after it is still a quote to the shell.
    ("'\u{301}", "''\\''\u{301}'"),
    ("x'\u{301}y", "'x'\\''\u{301}y'"),
    ("`\u{301};touch PWNED;`\u{301}", "'`\u{301};touch PWNED;`\u{301}'"),
  ])
  func `single quotes close and reopen around a quote, even one with a mark after it`(
    text: String,
    expected: String,
  ) {
    #expect(Array(ShellWord.quoting(text).utf8) == Array(expected.utf8))
  }

  @Test(arguments: [
    ("plain", "\"plain\""),
    ("\"", "\"\\\"\""),
    ("a\\b", "\"a\\\\b\""),
    ("$HOME", "\"\\$HOME\""),
    ("$(id)", "\"\\$(id)\""),
    ("`id`", "\"\\`id\\`\""),
    ("a\nb", "\"a\nb\""),
    // A backtick, dollar, quote or backslash with a mark after it is still one to the shell.
    ("`\u{301};touch PWNED;`\u{301}", "\"\\`\u{301};touch PWNED;\\`\u{301}\""),
    ("$\u{301}(id)", "\"\\$\u{301}(id)\""),
    ("\"\u{301}", "\"\\\"\u{301}\""),
    ("\\\u{301}", "\"\\\\\u{301}\""),
  ])
  func `double quotes escape what still means something, even with a mark after it`(
    text: String,
    expected: String,
  ) {
    #expect(Array(ShellWord.doubleQuoting(text).utf8) == Array(expected.utf8))
  }

  // MARK: - A real shell

  @Test(arguments: texts)
  func `a shell reads single quotes back as the text`(text: String) async throws {
    let shown = try await output(of: "printf %s " + ShellWord.quoting(text))

    #expect(Array(shown.utf8) == Array(text.utf8))
  }

  @Test(arguments: texts)
  func `a shell reads double quotes back as the text`(text: String) async throws {
    let shown = try await output(of: "printf %s " + ShellWord.doubleQuoting(text))

    #expect(Array(shown.utf8) == Array(text.utf8))
  }

  @Test
  func `a command hidden in a name with a mark after a backtick does not run`() async throws {
    let fixture = try ProcessFixture()
    let name = "`\u{301};touch PWNED;`\u{301}"

    _ = try await fixture.supervisor().run(
      fixture.request("echo " + ShellWord.doubleQuoting(name)),
    )

    #expect(!FileManager.default.fileExists(atPath: fixture.directory.location(of: "PWNED").path))
  }

  // MARK: - Reading

  @Test(arguments: texts)
  func `what is written as a word is read back as it, with nothing left`(text: String) throws {
    let written = ShellWord.quoting(text)

    let read = try #require(ShellWord.reading(written.unicodeScalars[...]))

    #expect(Array(read.word.utf8) == Array(text.utf8))
    #expect(read.rest.isEmpty)
  }

  @Test(arguments: [
    ("a'b' rest", "ab", " rest"),
    ("it\\'s rest", "it's", " rest"),
    ("it\"'\"s rest", "it's", " rest"),
    ("'a b'c;", "a bc", ";"),
    ("'\u{301}' x", "\u{301}", " x"),
    ("'it'\\''\u{301}s' x", "it'\u{301}s", " x"),
  ])
  func `a word is read as a shell reads it, however its quotes were written`(
    text: String,
    word: String,
    rest: String,
  ) throws {
    let read = try #require(ShellWord.reading(text.unicodeScalars[...]))

    #expect(Array(read.word.utf8) == Array(word.utf8))
    #expect(Array(String(read.rest).utf8) == Array(rest.utf8))
  }

  @Test(arguments: ["", " x", "'unclosed", "$x", ";"])
  func `text that does not start with a word has none`(text: String) {
    #expect(ShellWord.reading(text.unicodeScalars[...]) == nil)
  }
}
