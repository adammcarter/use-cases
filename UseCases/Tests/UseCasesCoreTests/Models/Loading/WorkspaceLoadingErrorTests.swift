import Testing
@testable import UseCasesCore

struct WorkspaceLoadingErrorTests {
  @Test
  func `an invalid workspace's message has each problem on its own line, in order`() {
    let error = WorkspaceLoadingError.invalid(problems: ["a.yml:2: one", "b.yml: two"])

    #expect(error.message == "a.yml:2: one\nb.yml: two")
  }

  @Test
  func `a refusal with a single message gives that message`() {
    #expect(WorkspaceLoadingError.noWorkspace(message: "no root").message == "no root")
    #expect(WorkspaceLoadingError.schemasUnavailable(message: "no schema").message == "no schema")
  }

  @Test
  func `an invalid workspace with one problem has no trailing line break`() {
    #expect(WorkspaceLoadingError.invalid(problems: ["a.yml: one"]).message == "a.yml: one")
  }
}
