import Testing
@testable import UseCasesTransformers

struct CargoTestTransformerTests {
  private static let lib = """
  pub fn lex() {}

  #[cfg(test)]
  mod tests {
    #[test]
    fn numbers_include_decimals() {
    }

    #[test]
    fn multiplication_sign_is_an_operator() {
    }

    #[test]
    fn precedence() {
    }
  }
  """

  private func workspace(console: String) throws -> ResultsWorkspace {
    let workspace = try ResultsWorkspace()

    try workspace.folder.write(
      "src/lib.rs",
      CargoTestTransformerTests.lib,
    )
    try workspace.folder.write(
      "tests/integration.rs",
      "#[test]\nfn full_expression_keeps_order() {\n}\n",
    )
    try workspace.writeReport(console)

    return workspace
  }

  @Test
  func `ok, FAILED and ignored are pass, fail and incomplete`() throws {
    let numbers = RequestLink.validation(
      "src/lib.rs",
      5,
      7,
      binding: "numbers",
    )
    let sign = RequestLink.validation(
      "src/lib.rs",
      9,
      11,
      binding: "sign",
    )
    let order = RequestLink.validation(
      "src/lib.rs",
      13,
      15,
      binding: "order",
    )
    let workspace = try workspace(
      console: """
      running 3 tests
         Running unittests src/lib.rs (target/debug/deps/lex-abc123)
      test tests::numbers_include_decimals ... ok
      test tests::multiplication_sign_is_an_operator ... ignored, not yet
      test tests::precedence ... FAILED

      test result: FAILED. 1 passed; 1 failed; 1 ignored
      """,
    )

    let response = try CargoTestTransformer().results(for: workspace.request(links: [
      numbers,
      sign,
      order,
    ]))

    #expect(response.status(of: numbers) == .pass)
    #expect(response.status(of: sign) == .incomplete)
    #expect(response.status(of: order) == .fail)
    #expect(response.results.first?.tests == ["src/lib.rs::tests::numbers_include_decimals"])
  }

  @Test
  func `an integration test is found in the file its Running line names`() throws {
    let link = RequestLink.validation(
      "tests/integration.rs",
      1,
      3,
    )
    let workspace = try workspace(
      console: """
           Running tests/integration.rs (target/debug/deps/integration-abc)
      test full_expression_keeps_order ... ok
      """,
    )

    let response = try CargoTestTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .pass)
    #expect(response.results.first?.tests == ["tests/integration.rs::full_expression_keeps_order"])
  }

  @Test
  func `a test not in the running file is looked for under src and tests`() throws {
    let link = RequestLink.validation(
      "tests/integration.rs",
      1,
      3,
    )
    let workspace = try workspace(
      console: """
         Running unittests src/lib.rs (target/debug/deps/lex-abc123)
      test full_expression_keeps_order ... ok
      """,
    )

    let response = try CargoTestTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `a test seen before any Running line is still found`() throws {
    let link = RequestLink.validation(
      "src/lib.rs",
      5,
      7,
    )
    let workspace = try workspace(console: "test tests::numbers_include_decimals ... ok\n")

    let response = try CargoTestTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .pass)
    #expect(response.results.first?.tests == ["tests::numbers_include_decimals"])
  }

  @Test
  func `a function declared twice is left unlinked with a note`() throws {
    let workspace = try workspace(console: "test tests::precedence ... ok\n")

    try workspace.folder.write(
      "src/other.rs",
      "fn precedence() {}\n",
    )

    let response = try CargoTestTransformer().results(for: workspace.request(links: []))

    #expect(response.unlinked.count == 1)
    #expect(response.unlinked.first?.file == nil)
    #expect(response
      .diagnostics == ["test tests::precedence matches several functions; left unlinked"])
  }

  @Test
  func `a test with no declaration is unlinked`() throws {
    let workspace = try workspace(console: "test tests::ghost ... ok\n")

    let response = try CargoTestTransformer().results(for: workspace.request(links: []))

    #expect(response.unlinked == [UnlinkedTest(
      test: "tests::ghost",
      file: nil,
      line: nil,
      status: .pass,
    )])
  }

  @Test(arguments: [
    "test result: ok. 3 passed",
    "running 3 tests",
    "test src/lib.rs - lex (line 3) ... ok",
    "    Doc-tests lex",
    "test tests::x ... bench: 3 ns",
    "",
  ])
  func `console lines that are not a test's result are ignored`(line: String) throws {
    let workspace = try workspace(console: line + "\n")

    let response = try CargoTestTransformer().results(for: workspace.request(links: []))

    #expect(response.unlinked.isEmpty)
    #expect(response.results.isEmpty)
  }

  @Test
  func `console output that is not UTF-8 is still read`() throws {
    let workspace = try workspace(console: "")

    try workspace.folder.writeBytes(
      ResultsWorkspace.reportName,
      Array("test tests::precedence ... ok\n".utf8) + [0xFF, 0xFE, 0x0A],
    )

    let response = try CargoTestTransformer().results(
      for: workspace.request(links: [.validation(
        "src/lib.rs",
        13,
        15,
      )]),
    )

    #expect(response.results.count == 1)
  }

  @Test
  func `no report is a failure that names it`() throws {
    let workspace = try ResultsWorkspace()

    #expect(throws: TransformerFailure.self) {
      try CargoTestTransformer().results(for: workspace.request(links: []))
    }
  }

  @Test
  func `one stray byte in the console does not garble the names around it`() throws {
    let link = RequestLink.validation(
      "src/lib.rs",
      1,
      9,
    )
    let workspace = try ResultsWorkspace()
    let console = Array("test tests::café_works ... FAILED\n".utf8) + [0xFF, 0x0A]

    try workspace.folder.write(
      "src/lib.rs",
      """
      mod tests {
        #[test]
        fn café_works() {
        }
      }
      """,
    )
    try workspace.folder.writeBytes(
      ResultsWorkspace.reportName,
      console,
    )

    let response = try CargoTestTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .fail)
  }

  @Test
  func `paths and searches start at the folder cargo test ran in`() throws {
    let workspace = try ResultsWorkspace()
    let inCrate = RequestLink.validation(
      "crate/src/lib.rs",
      1,
      9,
    )

    try workspace.folder.write(
      "crate/src/lib.rs",
      """
      mod tests {
        fn precedence() {
        }
      }
      """,
    )
    try workspace.folder.write(
      "src/lib.rs",
      """
      mod other {
        fn precedence() {
        }
      }
      """,
    )
    try workspace.writeReport(
      """
         Running unittests src/lib.rs (target/debug/deps/crate-abc)
      test tests::precedence ... FAILED
      """,
    )

    let fromCrate = try CargoTestTransformer().results(
      for: workspace.request(
        links: [inCrate],
        workingDirectory: "crate",
      ),
    )
    let fromRoot = try CargoTestTransformer().results(for: workspace.request(links: [inCrate]))

    #expect(fromCrate.status(of: inCrate) == .fail)
    #expect(fromRoot.status(of: inCrate) == nil)
  }

  @Test
  func `a line separator inside the console does not hide a result`() throws {
    let link = RequestLink.validation(
      "src/lib.rs",
      13,
      15,
    )
    let workspace = try workspace(
      console: "noise \u{2028} \u{85} noise\ntest tests::precedence ... FAILED\n",
    )

    let response = try CargoTestTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .fail)
  }
}
