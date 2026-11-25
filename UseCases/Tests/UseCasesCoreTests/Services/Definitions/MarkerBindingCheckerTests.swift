import Testing
@testable import UseCasesCore

struct MarkerBindingCheckerTests {
  private let checker = MarkerBindingChecker()
  private let markerBinding = #"{"id":"x","kind":"marker"}"#
  private let manualBinding =
    #"{"id":"y","kind":"manual","locator":{"file":"src/a.swift"}}"#

  private func check(_ useCase: JSONMembers) throws -> MarkerBindingFindings {
    try checker.check(
      authored(DefinitionSamples.file(useCase)),
      file: workspacePath("use-cases/login.yml"),
    )
  }

  @Test
  func `a file with only manual bindings has nothing to say`() throws {
    let found = try check(DefinitionSamples.useCase.setting("bindings", "[\(manualBinding)]"))

    #expect(found.diagnostics.isEmpty)
    #expect(found.bindingPaths.isEmpty)
  }

  @Test
  func `a marker binding on a use case is refused in words that say it needs no entry`() throws {
    let found = try check(DefinitionSamples.useCase.setting("bindings", "[\(markerBinding)]"))
    let diagnostic = try #require(found.diagnostics.first)

    #expect(found.diagnostics.count == 1)
    #expect(diagnostic.code == .markerBindingInYAML)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.message.hasPrefix("binding 'x' of use case 'authenticate' is kind: marker"))
    #expect(diagnostic.message.contains("need no entry"))
    #expect(
      found.bindingPaths == [[.key("use_cases"), .index(0), .key("bindings"), .index(0)]],
    )
  }

  @Test
  func `a marker binding on a route names the route`() throws {
    let route = DefinitionSamples.route.setting("bindings", "[\(manualBinding),\(markerBinding)]")
    let found = try check(
      DefinitionSamples.useCase.setting("validation", "[\(route.json)]"),
    )
    let diagnostic = try #require(found.diagnostics.first)

    #expect(found.diagnostics.count == 1)
    #expect(
      diagnostic.message.hasPrefix(
        "binding 'x' of route 'unit-tests' of use case 'authenticate' is kind: marker",
      ),
    )
    #expect(
      found.bindingPaths == [[
        .key("use_cases"), .index(0), .key("validation"), .index(0), .key("bindings"), .index(1),
      ]],
    )
  }

  @Test
  func `a failure under a marker binding is covered and one elsewhere is not`() throws {
    let found = try check(DefinitionSamples.useCase.setting("bindings", "[\(markerBinding)]"))
    let under = SchemaFailure(
      path: [.key("use_cases"), .index(0), .key("bindings"), .index(0), .key("kind")],
      keyword: .enumeration,
      message: "'marker' is not allowed",
    )
    let beside = SchemaFailure(
      path: [.key("use_cases"), .index(0), .key("title")],
      keyword: .type,
      message: "42 is not of type 'string'",
    )

    #expect(found.covers(under))
    #expect(!found.covers(beside))
  }

  @Test(arguments: [#"[]"#, #"{"use_cases":5}"#, #"{"use_cases":[7,{"bindings":3}]}"#])
  func `what is not the shape of a definition file is left to the schema`(json: String) throws {
    let found = try checker.check(
      authored(json),
      file: workspacePath("use-cases/login.yml"),
    )

    #expect(found.diagnostics.isEmpty)
  }
}
