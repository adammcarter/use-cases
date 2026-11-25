import Testing
@testable import UseCasesCore

struct WorkspacePathErrorTests {
  @Test(
    arguments: [
      (WorkspacePathError.empty, "", "cannot be empty"),
      (.absolute("/x"), "/x", "not begin with '/'"),
      (.driveLetter("C:/x"), "C:/x", "drive letter"),
      (.parentSegment("a/../b"), "a/../b", "'..'"),
      (.backslash("a\\b"), "a\\b", "never '\\'"),
      (.controlCharacter("\n", within: "a\n"), "a\n", "control character '\\n'"),
      (.notUTF8("bad\\xFF.js"), "bad\\xFF.js", "not valid UTF-8"),
      (.notCanonical("./bar", canonical: "bar"), "./bar", "write 'bar'"),
      (.notCanonical("a//b", canonical: "a/b"), "a//b", "write 'a/b'"),
      (.notCanonical("a/", canonical: "a"), "a/", "write 'a'"),
      (.notCanonical("./c:/x", canonical: nil), "./c:/x", "cannot be empty or '.'"),
    ],
  )
  func `an error names the text and says what is wrong with it`(
    error: WorkspacePathError,
    text: String,
    fragment: String,
  ) {
    #expect(error.offendingText == text)
    #expect(error.reason.contains(fragment))
    #expect(error.description == "'\(text)' is not a valid path: \(error.reason)")
  }
}
