import Foundation
import Testing
@testable import UseCasesCore

struct InitTemplatesTests {
  /// A workspace made of the files `init` writes, loaded by the real loader.
  private func workspace(prefix: String?) throws -> LoadedWorkspace {
    let namespace = try prefix.map { text in
      try Namespace(validating: text)
    }
    let fixture = try WorkspaceFixture(
      rootConfiguration: InitTemplates.workspace(prefix: namespace),
    )
    try fixture.write(
      "use-cases/example.yml",
      InitTemplates.example,
    )
    try fixture.write(
      "use-case-groups.yml",
      InitTemplates.groups(prefix: namespace),
    )
    try fixture.write(
      "use-cases-bridge.yml",
      InitTemplates.bridge,
    )

    return try fixture.loaded()
  }

  @Test(arguments: [nil, "shop", "shop.web"])
  func `the files load together as a workspace with one draft example`(
    prefix: String?,
  ) throws {
    let loaded = try workspace(prefix: prefix)
    let expected = prefix.map { prefix in "\(prefix).example.getting-started" }
      ?? "example.getting-started"

    #expect(loaded.useCases.map(\.identifier.text) == [expected])
    #expect(loaded.summary.draft == 1)
  }

  @Test(arguments: [nil, "shop"])
  func `the smoke group selects the example, whatever the prefix`(
    prefix: String?,
  ) throws {
    let loaded = try workspace(prefix: prefix)

    #expect(loaded.groups.map(\.name.text) == ["smoke"])
    #expect(loaded.groups.first?.members == loaded.useCases.map(\.identifier.text))
  }

  @Test
  func `the bridge template has no validation and no link`() throws {
    let loaded = try workspace(prefix: nil)

    #expect(loaded.bridge?.validations.isEmpty == true)
    #expect(loaded.bridge?.links.isEmpty == true)
    #expect(InitTemplates.bridge.contains("your, test, command"))
  }

  @Test
  func `the example leaves its value tier as a comment and ends inside the use case`() {
    let lines = InitTemplates.example.split(
      separator: "\n",
      omittingEmptySubsequences: false,
    )

    #expect(lines.contains("    # value_tier: core"))
    #expect(InitTemplates.example.hasSuffix("validate.\n"))
    #expect(lines.dropLast().last?.hasPrefix("        ") == true)
  }

  @Test
  func `the example has a route with a procedure`() throws {
    let loaded = try workspace(prefix: nil)

    let routes = loaded.useCases.first?.definition.routes

    #expect(routes?.map(\.identifier.text) == ["manual-check"])
    #expect(routes?.first?.procedure != nil)
  }

  @Test
  func `the workspace file names the prefix when one is given and shows the option when not`(
  ) throws {
    let named = try InitTemplates.workspace(prefix: Namespace(validating: "shop"))
    let unnamed = InitTemplates.workspace(prefix: nil)

    #expect(
      named
        == "schema_version: 1\nroot: true\nprefix: shop\n\n"
        + "# discovery:        # optional: folders never searched for use cases or markers,\n"
        + "#   exclude:        # such as build output, or test data that holds marker "
        + "text as data.\n"
        + "#     - \"build/**\"\n"
        + "#     - \"tests/fixtures/**\"\n",
    )
    #expect(unnamed.contains("\n# prefix: shop"))
    #expect(!unnamed.contains("\nprefix:"))
  }

  @Test(arguments: [nil, "shop"])
  func `the workspace file shows discovery exclusions as a comment and excludes nothing`(
    prefix: String?,
  ) throws {
    let namespace = try prefix.map { text in
      try Namespace(validating: text)
    }
    let text = InitTemplates.workspace(prefix: namespace)
    let lines = text.split(
      separator: "\n",
      omittingEmptySubsequences: false,
    )

    #expect(lines.contains { line in
      line.hasPrefix("# discovery:")
    })
    #expect(lines.contains("#     - \"build/**\""))
    #expect(lines.contains("#     - \"tests/fixtures/**\""))
    #expect(text.contains("test data that holds marker text as data"))
    #expect(!lines.contains { line in
      line.hasPrefix("discovery:")
    })
    #expect(text.hasSuffix("\n"))
    #expect(!text.hasSuffix("\n\n"))

    let loaded = try workspace(prefix: prefix)

    #expect(loaded.scopes.first?.configuration.rootSettings?.discoveryExclusions.isEmpty == true)
  }

  @Test
  func `the exclusions, once uncommented, are valid and keep marker text in test data out`(
  ) throws {
    let active = InitTemplates.workspace(prefix: nil)
      .split(
        separator: "\n",
        omittingEmptySubsequences: false,
      )
      .map { line in
        ["# discovery:", "#   exclude:", "#     - "].contains { start in
          line.hasPrefix(start)
        } ? String(line.dropFirst(2)) : String(line)
      }
      .joined(separator: "\n")
    let fixture = try WorkspaceFixture(rootConfiguration: active)
    try fixture.write(
      "tests/fixtures/sample.swift",
      "// @use-case:example.getting-started#read-it\n",
    )

    let commented = try WorkspaceFixture(rootConfiguration: InitTemplates.workspace(prefix: nil))
    try commented.write(
      "tests/fixtures/sample.swift",
      "// @use-case:example.getting-started#read-it\n",
    )

    let loaded = try fixture.loaded()

    #expect(
      loaded.scopes.first?.configuration.rootSettings?.discoveryExclusions.count == 2,
    )
    #expect(try !fixture.resolved().isInvalid)
    #expect(try commented.resolved().isInvalid)
  }
}
