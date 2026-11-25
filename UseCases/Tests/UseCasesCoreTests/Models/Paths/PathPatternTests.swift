import Testing
@testable import UseCasesCore

struct PathPatternTests {
  @Test(
    arguments: [
      "*.json", "test_*", "schemas/**/*.json", "build/**", "**/node_modules/**", "**", "a?c",
      "vendor", "**/vendor", "a[b]{c}", "src/*/x", "*", "?", ".*", "**/**", "a.b", "caf\u{E9}/*",
      "My Tests/*.js", "*/*/*", String(repeating: "**/", count: 500) + "x", "cafe\u{301}/*",
      "caf?", "**/**/x", "x/**/**",
    ],
  )
  func `a pattern in the dialect is accepted and reads back as written`(text: String) throws {
    let pattern = try PathPattern(validating: text)

    #expect(pattern.text.isExactlyEqual(to: text))
    #expect(pattern.description.isExactlyEqual(to: text))
  }

  @Test(
    arguments: [
      ("", PathPatternError.invalidPath(.empty)),
      ("/x", .invalidPath(.absolute("/x"))),
      ("/", .invalidPath(.absolute("/"))),
      ("/**", .invalidPath(.absolute("/**"))),
      ("C:/x", .invalidPath(.driveLetter("C:/x"))),
      ("..", .invalidPath(.parentSegment(".."))),
      ("../x/**", .invalidPath(.parentSegment("../x/**"))),
      ("a/../b", .invalidPath(.parentSegment("a/../b"))),
      ("a\\b", .invalidPath(.backslash("a\\b"))),
      ("*.json\n", .invalidPath(.controlCharacter("\n", within: "*.json\n"))),
      ("a\tb", .invalidPath(.controlCharacter("\t", within: "a\tb"))),
      (".", .invalidPath(.notCanonical(".", canonical: nil))),
      ("./", .invalidPath(.notCanonical("./", canonical: nil))),
      ("./bar", .invalidPath(.notCanonical("./bar", canonical: "bar"))),
      ("./**", .invalidPath(.notCanonical("./**", canonical: "**"))),
      ("a/./b", .invalidPath(.notCanonical("a/./b", canonical: "a/b"))),
      ("a/.", .invalidPath(.notCanonical("a/.", canonical: "a"))),
      ("a//b", .invalidPath(.notCanonical("a//b", canonical: "a/b"))),
      ("a//**", .invalidPath(.notCanonical("a//**", canonical: "a/**"))),
      ("a/", .invalidPath(.notCanonical("a/", canonical: "a"))),
      ("build/**/", .invalidPath(.notCanonical("build/**/", canonical: "build/**"))),
      ("a**", .doubleStarNotWholeSegment("a**", within: "a**")),
      ("**a", .doubleStarNotWholeSegment("**a", within: "**a")),
      ("***", .doubleStarNotWholeSegment("***", within: "***")),
      ("build**", .doubleStarNotWholeSegment("build**", within: "build**")),
      ("x/a**/y", .doubleStarNotWholeSegment("a**", within: "x/a**/y")),
      ("**/*.json**", .doubleStarNotWholeSegment("*.json**", within: "**/*.json**")),
    ],
  )
  func `text outside the dialect is refused`(
    text: String,
    expected: PathPatternError,
  ) {
    #expect(throws: expected) {
      try PathPattern(validating: text)
    }
  }

  @Test(
    arguments: [
      ("*.json", "a.json", true),
      ("*.json", "a/b.json", false),
      ("*.json", "a.JSON", false),
      ("*.json", "a.jsonx", false),
      ("test_*", "test_a", true),
      ("test_*", "tests", false),
      ("a*c", "abc", true),
      ("a*c", "a/c", false),
      ("**/*.json", "a.json", true),
      ("**/*.json", "a/b/c.json", true),
      ("**/*.json", "a.txt", false),
      ("**/*.json", "a/b.txt", false),
      ("build/**", "build", true),
      ("build/**", "build/x/y", true),
      ("build/**", "builds", false),
      ("build/**", "src/build", false),
      ("schemas/**/*.json", "schemas/a.json", true),
      ("schemas/**/*.json", "schemas/x/y/a.json", true),
      ("schemas/**/*.json", "schema/a.json", false),
      ("**/node_modules/**", "node_modules", true),
      ("**/node_modules/**", "a/b/node_modules/c/d", true),
      ("**/node_modules/**", "node_modules_x", false),
      ("**", "anything/at/all", true),
      ("**", "x", true),
      ("a?c", "abc", true),
      ("a?c", "a-c", true),
      ("a?c", "ac", false),
      ("a?c", "abbc", false),
      ("a?c", "a/c", false),
      ("?", "ab", false),
      ("fixtures/?.json", "fixtures/a.json", true),
      ("Src/*", "src/a", false),
      ("src/*", "src/a", true),
      ("a[b]", "a[b]", true),
      ("a[b]", "ab", false),
      ("{a,b}", "a", false),
      ("a.b", "aXb", false),
      ("a/b", "a/b", true),
      ("a/b", "a", false),
      ("a/b", "a/b/c", false),
      ("src/*/x", "src/a/x", true),
      ("src/*/x", "src/x", false),
      ("src/*/x", "src/a/b/x", false),
      ("*a*a*b", "aaab", true),
      ("*a*a*b", "aab", true),
      ("*a*a*b", "aba", false),
      ("*a*a*b", "ab", false),
      ("**/**/x", "x", true),
      ("**/**/x", "a/b/x", true),
      ("**/**/x", "a/y", false),
      ("x/**/**", "x", true),
      ("x/**/**", "x/a/b", true),
      ("x/**/**", "y", false),
      ("**/**", "a", true),
      ("*", ".hidden", true),
      (".*", ".hidden", true),
      ("*", "a/.hidden", false),
      ("src/*", "src/.hidden", true),
      ("caf?", "caf\u{E9}", true),
      ("caf?", "cafe\u{301}", false),
      ("caf??", "cafe\u{301}", true),
      ("caf??", "caf\u{E9}", false),
      ("cafe\u{301}", "caf\u{E9}", false),
      ("cafe\u{301}", "cafe\u{301}", true),
      ("cafe\u{301}/*", "caf\u{E9}/a", false),
      ("caf\u{E9}/*", "cafe\u{301}/a", false),
      ("caf*", "cafe\u{301}", true),
      ("*\u{E9}", "cafe\u{301}", false),
      ("caf\u{E9}", "caf\u{E9}", true),
      ("caf\u{E9}", "cafe\u{301}", false),
      ("My Tests/*.js", "My Tests/add test.js", true),
    ],
  )
  func `a pattern matches exactly the paths the dialect says`(
    pattern: String,
    path: String,
    expected: Bool,
  ) throws {
    let matcher = try PathPattern(validating: pattern)

    #expect(try matcher.matches(WorkspacePath(validating: path)) == expected)
  }

  /// A matcher that backtracked would not end on these, so a hang shows as a run that does not
  /// end: nothing here is measured.
  @Test
  func `a long run of stars matches a long name without backtracking without end`() throws {
    let name = String(repeating: "a", count: 600) + "c"
    let pattern = try PathPattern(validating: String(repeating: "a*", count: 300) + "b")
    let path = try WorkspacePath(validating: name)

    #expect(!pattern.matches(path))
  }

  @Test
  func `many double stars across a deep path match without backtracking without end`() throws {
    let pattern = try PathPattern(validating: String(repeating: "**/a/", count: 200) + "x")
    let deep = try WorkspacePath(validating: String(repeating: "a/", count: 1000) + "x")
    let wrong = try WorkspacePath(validating: String(repeating: "a/", count: 1000) + "y")

    #expect(pattern.matches(deep))
    #expect(!pattern.matches(wrong))
  }

  @Test
  func `a run of double stars is one double star`() throws {
    let run = try PathPattern(validating: "a/**/**/**/b")
    let single = try PathPattern(validating: "a/**/b")

    #expect(run == single)
    #expect(run.segments.count == 3)
    #expect(run.text == "a/**/**/**/b")
  }

  @Test(
    arguments: [
      ("vendor", "vendor", true),
      ("vendor", "vendor/a/b.js", true),
      ("vendor/**", "vendor", true),
      ("vendor/**", "vendor/a", true),
      ("**/vendor", "vendor/a", true),
      ("**/vendor", "a/vendor/x/y", true),
      ("**/vendor", "vendors/x", false),
      ("vendor", "src/vendor/x", false),
      ("build/**", "src/build/x", false),
      ("*.json", "a.json/inner.txt", true),
      ("*.json", "a.txt", false),
      ("a/b", "a", false),
      ("a/b", "a/b/c", true),
      ("a/b", "a/c/b", false),
      ("**/.git/**", "x/.git/config", true),
      ("**/.git/**", "x/.github/config", false),
      ("**/**/vendor", "vendor/a", true),
      ("**/**/vendor", "a/b/vendor/c", true),
      ("**/**/vendor", "vendors/a", false),
      ("vendor/**/**", "vendor", true),
      ("cafe\u{301}", "caf\u{E9}/a", false),
      ("caf\u{E9}", "cafe\u{301}/a", false),
      ("caf\u{E9}", "caf\u{E9}/a", true),
    ],
  )
  func `a pattern that matches a folder excludes everything in it`(
    pattern: String,
    path: String,
    expected: Bool,
  ) throws {
    let matcher = try PathPattern(validating: pattern)

    #expect(try matcher.excludes(WorkspacePath(validating: path)) == expected)
  }

  @Test
  func `matching a path asks for exactly that path, not the folders above it`() throws {
    let pattern = try PathPattern(validating: "vendor")

    #expect(try pattern.matches(WorkspacePath(validating: "vendor")))
    #expect(try !pattern.matches(WorkspacePath(validating: "vendor/a")))
  }

  @Test
  func `the same text gives equal patterns`() throws {
    let first = try PathPattern(validating: "a/**/*.json")
    let second = try PathPattern(validating: "a/**/*.json")

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test
  func `one name in two Unicode forms gives two different patterns`() throws {
    let composed = try PathPattern(validating: "caf\u{E9}/*")
    let decomposed = try PathPattern(validating: "cafe\u{301}/*")

    #expect(composed != decomposed)
    #expect(Set([composed, decomposed]).count == 2)
  }
}
