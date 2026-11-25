import Testing
@testable import UseCasesTransformers

struct GoTestJSONTransformerTests {
  private func event(
    _ action: String,
    _ test: String,
    package: String = "example.com/shop/cart",
  ) -> String {
    GoTestStream.event(
      action,
      test,
      package: package,
    )
  }

  private func workspace(
    module: String = "module example.com/shop\n",
    testSource: String = """
    package cart

    func TestTotal(t *testing.T) {
    }

    func TestTax(t *testing.T) {
    }
    """,
  ) throws -> ResultsWorkspace {
    let workspace = try ResultsWorkspace()

    try workspace.folder.write(
      "go.mod",
      module,
    )
    try workspace.folder.write(
      "cart/cart_test.go",
      testSource,
    )

    return workspace
  }

  @Test
  func `each top-level test is found by its function and its worst outcome wins`() throws {
    let workspace = try workspace()
    let total = RequestLink.validation(
      "cart/cart_test.go",
      3,
      4,
      binding: "total",
    )
    let tax = RequestLink.validation(
      "cart/cart_test.go",
      6,
      7,
      binding: "tax",
    )

    try workspace.writeReport(
      [
        event(
          "pass",
          "TestTotal/small",
        ),
        event(
          "pass",
          "TestTotal",
        ),
        event(
          "pass",
          "TestTax/low",
        ),
        event(
          "fail",
          "TestTax/high",
        ),
        event(
          "fail",
          "TestTax",
        ),
      ].joined(separator: "\n") + "\n",
    )

    let response = try GoTestJSONTransformer().results(for: workspace.request(links: [total, tax]))

    #expect(response.status(of: total) == .pass)
    #expect(response.status(of: tax) == .fail)
    #expect(
      response.results.first { result in
        result.link == total.key
      }?.tests == ["example.com/shop/cart.TestTotal"],
    )
  }

  @Test
  func `a skipped test is incomplete`() throws {
    let workspace = try workspace()
    let link = RequestLink.validation(
      "cart/cart_test.go",
      3,
      4,
    )

    try workspace.writeReport(event(
      "skip",
      "TestTotal",
    ) + "\n")

    let response = try GoTestJSONTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .incomplete)
  }

  @Test
  func `a test with no link is unlinked with its place`() throws {
    let workspace = try workspace()

    try workspace.writeReport(event(
      "pass",
      "TestTax",
    ) + "\n")

    let response = try GoTestJSONTransformer().results(
      for: workspace.request(links: [.validation(
        "cart/cart_test.go",
        3,
        4,
      )]),
    )

    #expect(
      response.unlinked == [
        UnlinkedTest(
          test: "example.com/shop/cart.TestTax",
          file: "cart/cart_test.go",
          line: 6,
          status: .pass,
        ),
      ],
    )
  }

  @Test
  func `a test with no declaration, or in another module, is unlinked with no place`() throws {
    let workspace = try workspace()

    try workspace.writeReport(
      [
        event(
          "pass",
          "TestGone",
        ),
        event(
          "pass",
          "TestA",
          package: "other.org/lib",
        ),
        event(
          "pass",
          "TestNoFolder",
          package: "example.com/shop/missing",
        ),
      ].joined(separator: "\n") + "\n",
    )

    let response = try GoTestJSONTransformer().results(for: workspace.request(links: []))

    #expect(response.unlinked.count == 3)
    #expect(response.unlinked.allSatisfy { $0.file == nil && $0.line == nil })
  }

  @Test
  func `a test declared twice in a package is left unlinked with a note`() throws {
    let workspace = try workspace(
      testSource: """
      func TestTotal(t *testing.T) {
      }
      func TestTotal(t *testing.T) {
      }
      """,
    )

    try workspace.writeReport(event(
      "pass",
      "TestTotal",
    ) + "\n")

    let response = try GoTestJSONTransformer().results(
      for: workspace.request(links: [.validation(
        "cart/cart_test.go",
        1,
        2,
      )]),
    )

    #expect(response.results.isEmpty)
    #expect(response
      .diagnostics == ["example.com/shop/cart.TestTotal is declared more than once; left unlinked"])
  }

  @Test
  func `the module folder comes from the working folder, or the module setting`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "checkout/cart/cart_test.go",
      1,
      2,
    )

    try workspace.folder.write(
      "checkout/go.mod",
      "module example.com/shop\n",
    )
    try workspace.folder.write(
      "checkout/cart/cart_test.go",
      "func TestTotal(t *testing.T)\n",
    )
    try workspace.writeReport(event(
      "pass",
      "TestTotal",
    ) + "\n")

    let fromWorkingFolder = try GoTestJSONTransformer().results(
      for: workspace.request(
        links: [link],
        workingDirectory: "checkout",
      ),
    )
    let fromSetting = try GoTestJSONTransformer().results(
      for: workspace.request(
        links: [link],
        settings: ["module": .string("checkout")],
      ),
    )

    #expect(fromWorkingFolder.status(of: link) == .pass)
    #expect(fromSetting.status(of: link) == .pass)
  }

  @Test
  func `no go mod is a failure that names it`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.writeReport(event(
      "pass",
      "TestTotal",
    ) + "\n")

    #expect(throws: TransformerFailure.self) {
      try GoTestJSONTransformer().results(for: workspace.request(links: []))
    }
  }

  @Test
  func `no report is a failure that names it`() throws {
    let workspace = try workspace()

    #expect(throws: TransformerFailure.self) {
      try GoTestJSONTransformer().results(for: workspace.request(links: []))
    }
  }

  @Test(arguments: ["./checkout", "checkout/", "./checkout/", "checkout//", "./checkout/./"])
  func `the module setting is read in the workspace's spelling`(setting: String) throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "checkout/cart/cart_test.go",
      1,
      2,
    )

    try workspace.folder.write(
      "checkout/go.mod",
      "module example.com/shop\n",
    )
    try workspace.folder.write(
      "checkout/cart/cart_test.go",
      "func TestTotal(t *testing.T)\n",
    )
    try workspace.writeReport(event(
      "pass",
      "TestTotal",
    ) + "\n")

    let response = try GoTestJSONTransformer().results(
      for: workspace.request(
        links: [link],
        settings: ["module": .string(setting)],
      ),
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test(arguments: [".", "./", ""])
  func `the module setting may name the code root`(setting: String) throws {
    let workspace = try workspace()
    let link = RequestLink.validation(
      "cart/cart_test.go",
      3,
      4,
    )

    try workspace.writeReport(event(
      "pass",
      "TestTotal",
    ) + "\n")

    let response = try GoTestJSONTransformer().results(
      for: workspace.request(
        links: [link],
        settings: ["module": .string(setting)],
      ),
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test(arguments: ["../outside", "a/../b", "/abs/path", "c:\\win", "back\\slash", "C:folder"])
  func `a module setting that is no folder inside the workspace is refused`(
    setting: String,
  ) throws {
    let workspace = try workspace()

    try workspace.writeReport(event(
      "pass",
      "TestTotal",
    ) + "\n")

    #expect(throws: TransformerFailure.settingInvalid(
      name: "module",
      expected: "a folder inside the workspace",
    )) {
      try GoTestJSONTransformer().results(
        for: workspace.request(
          links: [],
          settings: ["module": .string(setting)],
        ),
      )
    }
  }
}
