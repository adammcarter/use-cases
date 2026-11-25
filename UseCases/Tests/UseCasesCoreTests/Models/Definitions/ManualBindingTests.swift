import Testing
@testable import UseCasesCore

struct ManualBindingTests {
  private func binding(_ json: String) throws -> ManualBinding {
    try ManualBinding(authored: AuthoredObject(authored(json), at: "bindings[0]"))
  }

  @Test
  func `a manual binding has an id and a locator`() throws {
    let binding = try binding(
      #"{"id":"legacy-login","kind":"manual","locator":{"file":"src/login.py"}}"#,
    )

    #expect(binding.identifier.text == "legacy-login")
    #expect(binding.locator.file.text == "src/login.py")
  }

  @Test
  func `a marker binding in YAML is refused`() {
    #expect(
      throws: AuthoredShapeError.unknownChoice(
        location: "bindings[0].kind",
        text: "marker",
      ),
    ) {
      try binding(#"{"id":"x","kind":"marker","locator":{"file":"a"}}"#)
    }
  }

  @Test
  func `bindings are read from a list in the order written, and an absent list is empty`() throws {
    let object = try AuthoredObject(
      authored(
        """
        {"bindings":[
        {"id":"b","kind":"manual","locator":{"file":"b"}},
        {"id":"a","kind":"manual","locator":{"file":"a"}}]}
        """,
      ),
      at: "",
    )

    #expect(try object.manualBindings("bindings").map(\.identifier.text) == ["b", "a"])
    #expect(try object.manualBindings("other").isEmpty)
  }
}
