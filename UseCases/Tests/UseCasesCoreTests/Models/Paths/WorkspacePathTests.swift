import Testing
@testable import UseCasesCore

struct WorkspacePathTests {
  private let composed = "src/caf\u{E9}.js"
  private let decomposed = "src/cafe\u{301}.js"

  @Test(
    arguments: [
      "a", "use-cases.yml", "src/app.js", "My Tests/add test.test.js", "tests/caf\u{E9}.test.js",
      "tests/a@b:c.test.js", ".use-cases/runs", ".hidden", "...", "..a", "a..b", "a/b..", "1:b",
      "ab:c", "a b ", "\u{1F600}/x", "a\u{85}b", ".", "tests/cafe\u{301}.test.js", String(
        repeating: "dir/",
        count: 2500,
      ) + "file",
    ],
  )
  func `a workspace-relative path is accepted exactly as written`(text: String) throws {
    let path = try WorkspacePath(validating: text)

    #expect(path.text.isExactlyEqual(to: text))
    #expect(path.description.isExactlyEqual(to: text))
  }

  @Test(arguments: [".", "..a", "a.", ".a", "a/.b"])
  func `only the whole path dot is the workspace root`(text: String) throws {
    #expect(try WorkspacePath(validating: text).isRoot == (text == "."))
  }

  @Test(
    arguments: [
      ("", WorkspacePathError.empty),
      ("/x", .absolute("/x")),
      ("/", .absolute("/")),
      ("C:/x", .driveLetter("C:/x")),
      ("c:", .driveLetter("c:")),
      ("z:file", .driveLetter("z:file")),
      ("..", .parentSegment("..")),
      ("../x", .parentSegment("../x")),
      ("a/..", .parentSegment("a/..")),
      ("a/../b", .parentSegment("a/../b")),
      ("a\\b", .backslash("a\\b")),
      ("\\", .backslash("\\")),
      ("a\u{0}b", .controlCharacter("\u{0}", within: "a\u{0}b")),
      ("a\tb", .controlCharacter("\t", within: "a\tb")),
      ("a\nb", .controlCharacter("\n", within: "a\nb")),
      ("a.yml\n", .controlCharacter("\n", within: "a.yml\n")),
      ("a.yml\r\n", .controlCharacter("\r", within: "a.yml\r\n")),
      ("a\u{1F}b", .controlCharacter("\u{1F}", within: "a\u{1F}b")),
      ("a\u{7F}b", .controlCharacter("\u{7F}", within: "a\u{7F}b")),
      ("./bar", .notCanonical("./bar", canonical: "bar")),
      ("a/./b", .notCanonical("a/./b", canonical: "a/b")),
      ("a/.", .notCanonical("a/.", canonical: "a")),
      ("././a", .notCanonical("././a", canonical: "a")),
      ("a//b", .notCanonical("a//b", canonical: "a/b")),
      ("a///b", .notCanonical("a///b", canonical: "a/b")),
      ("a/", .notCanonical("a/", canonical: "a")),
      ("a/b/", .notCanonical("a/b/", canonical: "a/b")),
      ("./", .notCanonical("./", canonical: ".")),
      (".//", .notCanonical(".//", canonical: ".")),
      ("./c:/x", .notCanonical("./c:/x", canonical: nil)),
    ],
  )
  func `a path that is not workspace-relative is refused`(
    text: String,
    expected: WorkspacePathError,
  ) {
    #expect(throws: expected) {
      try WorkspacePath(validating: text)
    }
  }

  @Test(
    arguments: [
      ("a", ["a"]),
      ("src/app.js", ["src", "app.js"]),
      ("a/b/c", ["a", "b", "c"]),
      ("My Tests/add test.js", ["My Tests", "add test.js"]),
    ],
  )
  func `the segments are the names between the slashes`(
    text: String,
    expected: [String],
  ) throws {
    #expect(try WorkspacePath(validating: text).segments == expected)
  }

  @Test
  func `one name in two Unicode forms is two different paths`() throws {
    let first = try WorkspacePath(validating: composed)
    let second = try WorkspacePath(validating: decomposed)

    #expect(first != second)
    #expect(Set([first, second]).count == 2)
    #expect((first < second) != (second < first))
  }

  @Test
  func `the same spelling is one path`() throws {
    let first = try WorkspacePath(validating: composed)
    let second = try WorkspacePath(validating: composed)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test(
    arguments: [
      ("a", "b"),
      ("a", "ab"),
      ("a", "a/b"),
      ("src/a.js", "src/b.js"),
      ("a.js", "b.js"),
    ],
  )
  func `a path sorts before a later one`(
    smaller: String,
    larger: String,
  ) throws {
    let first = try WorkspacePath(validating: smaller)
    let second = try WorkspacePath(validating: larger)

    #expect(first < second)
    #expect(!(second < first))
    #expect([second, first].sorted() == [first, second])
  }
}
