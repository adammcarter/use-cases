import Testing
@testable import UseCasesCore

struct InitErrorTests {
  @Test(arguments: [
    (
      InitError.invalidPrefix(text: "Shop", reason: "no capitals"),
      "'Shop' is not a valid prefix: no capitals",
    ),
    (InitError.notAFolder(path: "/w/x"), "'/w/x' is not a folder"),
    (
      InitError.invalidWorkspace(problems: ["use-cases.yml:1: a", "use-cases.yml:2: b"]),
      "use-cases.yml:1: a\nuse-cases.yml:2: b",
    ),
    (
      InitError.obstructed(path: "use-cases-bridge.yml", reason: "it is a folder, not a file"),
      "use-cases-bridge.yml cannot be used: it is a folder, not a file",
    ),
    (InitError.unavailable(message: "no schemas"), "no schemas"),
  ])
  func `a refusal is told in one place with the words the person needs`(
    error: InitError,
    message: String,
  ) {
    #expect(error.message == message)
  }

  @Test
  func `a workspace root that is not one, and one that is inside another, say so`() {
    let child = InitError.notWorkspaceRoot(path: "/w/svc").message
    let inside = InitError.insideWorkspace(folder: "/w/svc", root: "/w").message

    #expect(child.contains("is not a workspace root"))
    #expect(inside.contains("is inside the workspace at '/w'"))
  }

  @Test
  func `a different prefix is told with the one the workspace has, or that it has none`() {
    let named = InitError.differentPrefix(existing: "shop", asked: "other").message
    let unnamed = InitError.differentPrefix(existing: nil, asked: "other").message

    #expect(named
      .contains("--prefix 'other' differs from the workspace, which has the prefix 'shop'"))
    #expect(unnamed.contains("which has no prefix"))
    #expect(named.contains("never changes a prefix"))
  }
}
