import Testing
@testable import UseCasesTransformers

struct GlobPatternTests {
  @Test(arguments: [
    ("src/test/**/*.java", "src/test/a/b/FooTest.java", true),
    ("src/test/**/*.java", "src/test/FooTest.java", true),
    ("src/test/**/*.java", "src/main/FooTest.java", false),
    ("src/test/**/*.java", "src/test/a/FooTest.kt", false),
    ("tests/**/*.c", "tests/x.c", true),
    ("tests/*.c", "tests/a/x.c", false),
    ("tests/*.c", "tests/x.c", true),
    ("*.swift", "A.swift", true),
    ("*.swift", "dir/A.swift", false),
    ("**/*.swift", "dir/deep/A.swift", true),
    ("**/*.swift", "A.swift", true),
    ("Tests/**", "Tests/a/b.swift", true),
    ("a?c.txt", "abc.txt", true),
    ("a?c.txt", "ac.txt", false),
    ("test/**/*.js", "test/a.js", true),
    ("exact/file.txt", "exact/file.txt", true),
    ("exact/file.txt", "exact/file.txt.bak", false),
    ("*", "", false),
    ("a*b*c", "aXXbYYc", true),
    ("a*b*c", "aXXbYY", false),
  ])
  func `a glob matches paths the way globs do`(
    pattern: String,
    path: String,
    expected: Bool,
  ) {
    #expect(GlobPattern(pattern).matches(path) == expected)
  }

  @Test
  func `a star never crosses a folder`() {
    #expect(!GlobPattern("src/*/X.java").matches("src/a/b/X.java"))
    #expect(GlobPattern("src/*/X.java").matches("src/a/X.java"))
  }
}
