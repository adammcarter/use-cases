import Testing
@testable import UseCasesTransformers

struct FolderPathTests {
  @Test(arguments: [
    ("svc", "svc"),
    ("./svc", "svc"),
    ("svc/", "svc"),
    ("./svc/", "svc"),
    ("svc//pkg", "svc/pkg"),
    ("a/./b", "a/b"),
    (".", ""),
    ("./", ""),
    ("", ""),
  ])
  func `a folder is spelled the way paths are`(
    text: String,
    expected: String,
  ) {
    #expect(FolderPath.normalised(text) == expected)
  }

  @Test(arguments: [
    "/abs",
    "/",
    "..",
    "../x",
    "a/../b",
    "a/..",
    "c:\\win",
    "C:x",
    "a\\b",
    "a\u{0}b",
    "a\nb"
  ])
  func `what cannot name a folder inside the workspace has no spelling`(text: String) {
    #expect(FolderPath.normalised(text) == nil)
  }

  @Test
  func `a colon after the first two characters is just a name`() {
    #expect(FolderPath.normalised("ab:c") == "ab:c")
  }
}
