import Testing
@testable import UseCasesCore

struct TransformerReferenceTests {
  @Test
  func `a name without a slash is a bundled transformer`() throws {
    #expect(try TransformerReference(text: "swift-testing") == .bundled("swift-testing"))
  }

  @Test
  func `a name with a slash is a program path from the workspace root`() throws {
    #expect(try TransformerReference(text: "tools/read-junit") ==
      .program(WorkspacePath(validating: "tools/read-junit")))
  }

  @Test(arguments: ["/abs/tool", "../tool", "tools//tool", "tools/"])
  func `a path off the workspace grammar is refused`(text: String) {
    #expect(throws: WorkspacePathError.self) {
      try TransformerReference(text: text)
    }
  }

  @Test
  func `the bundled names are the catalogue's`() {
    #expect(BundledTransformer.names.count == 8)
    #expect(BundledTransformer.names.contains("exit-code"))
    #expect(!BundledTransformer.names.contains("record"))
  }
}
