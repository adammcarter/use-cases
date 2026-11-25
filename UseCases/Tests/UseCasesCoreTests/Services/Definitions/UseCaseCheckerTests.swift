import Testing
@testable import UseCasesCore

struct UseCaseCheckerTests {
  private let checker = UseCaseChecker()

  private func check(_ members: JSONMembers) throws -> [Diagnostic] {
    let useCase = try UseCaseDefinition(
      authored: AuthoredObject(
        authored(members.json),
        at: "",
      ),
    )

    return try checker.check(
      useCase,
      file: workspacePath("use-cases/math.yml"),
    )
  }

  private func scenarios(_ ids: [String]) -> String {
    let scenarios = ids.map { id in
      DefinitionSamples.scenario(id: id).json
    }

    return "[" + scenarios.joined(separator: ",") + "]"
  }

  private func routes(_ routes: [(id: String, covers: [String])]) -> String {
    let written = routes.map { route in
      DefinitionSamples.route(id: route.id, covers: route.covers).json
    }

    return "[" + written.joined(separator: ",") + "]"
  }

  @Test
  func `a use case with no problem has no diagnostic`() throws {
    #expect(try check(DefinitionSamples.useCase).isEmpty)
    #expect(try check(DefinitionSamples.draft).isEmpty)
  }

  @Test
  func `a route covering an unknown scenario is told as the acceptance tests word it`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("id", #""add""#)
        .setting("scenarios", scenarios(["adds"]))
        .setting("validation", routes([(id: "unit-tests", covers: ["adds", "subtracts"])])),
    )

    let diagnostic = try #require(found.first)
    #expect(found.count == 1)
    #expect(diagnostic.code == .unknownScenario)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.file.text == "use-cases/math.yml")
    #expect(
      diagnostic.message
        == "validation route 'unit-tests' of use case 'add' covers unknown scenarios ['subtracts']",
    )
  }

  @Test
  func `every unknown scenario is listed in the order written`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("scenarios", scenarios(["known"]))
        .setting("validation", routes([(id: "unit-tests", covers: ["z", "known", "a", "m"])])),
    )

    #expect(found.first?.message.hasSuffix("covers unknown scenarios ['z', 'a', 'm']") == true)
  }

  @Test
  func `each route is judged on its own`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("scenarios", scenarios(["known"]))
        .setting(
          "validation",
          routes([
            (id: "first", covers: ["known"]),
            (id: "second", covers: ["gone"]),
            (id: "third", covers: ["missing"]),
          ]),
        ),
    )

    #expect(found.count == 2)
    #expect(found[0].message.hasPrefix("validation route 'second'"))
    #expect(found[1].message.hasPrefix("validation route 'third'"))
  }

  @Test
  func `a use case with routes and no scenarios has every cover unknown`() throws {
    let found = try check(
      DefinitionSamples.draft.setting(
        "validation",
        routes([(id: "unit-tests", covers: ["adds"])]),
      ),
    )

    #expect(found.first?.message.hasSuffix("covers unknown scenarios ['adds']") == true)
  }

  @Test
  func `two scenarios with one id make the use case INVALID`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("id", #""add""#)
        .setting("scenarios", scenarios(["adds", "adds"]))
        .setting("validation", routes([(id: "unit-tests", covers: ["adds"])])),
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .duplicateScenario)
    #expect(
      found.first?.message == "use case 'add' has two scenarios with id 'adds'",
    )
  }

  @Test
  func `two routes with one id make the use case INVALID`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("id", #""add""#)
        .setting(
          "validation",
          routes([
            (id: "unit-tests", covers: ["valid-credentials"]),
            (id: "unit-tests", covers: ["valid-credentials"]),
          ]),
        ),
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .duplicateRoute)
    #expect(
      found.first?.message
        == "use case 'add' has two routes with id 'unit-tests'",
    )
  }

  @Test
  func `an id used three times is reported once, and each repeated id once`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("scenarios", scenarios(["a", "b", "a", "b", "a"]))
        .setting("validation", routes([(id: "unit-tests", covers: ["a", "b"])])),
    )

    #expect(found.map(\.code) == [.duplicateScenario, .duplicateScenario])
  }

  @Test
  func `the same id as a scenario and as a route is no duplicate`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("scenarios", scenarios(["same"]))
        .setting("validation", routes([(id: "same", covers: ["same"])])),
    )

    #expect(found.isEmpty)
  }

  @Test
  func `the same ids in two use cases are no duplicate`() throws {
    #expect(try check(DefinitionSamples.useCase).isEmpty)
    #expect(try check(DefinitionSamples.useCase.setting("id", #""other""#)).isEmpty)
  }

  @Test
  func `the diagnostics come back sorted`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("scenarios", scenarios(["a", "a"]))
        .setting(
          "validation",
          routes([(id: "r", covers: ["a"]), (id: "r", covers: ["zzz"])]),
        ),
    )

    #expect(found.count == 3)
    #expect(found == found.sorted())
  }

  private func bindings(_ bindings: [JSONMembers]) -> String {
    "[" + bindings.map(\.json).joined(separator: ",") + "]"
  }

  @Test
  func `two bindings of a use case with one id make it INVALID`() throws {
    let found = try check(
      DefinitionSamples.useCase
        .setting("id", #""add""#)
        .setting(
          "bindings",
          bindings([DefinitionSamples.binding(id: "b"), DefinitionSamples.binding(id: "b")]),
        ),
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .duplicateBinding)
    #expect(found.first?.message == "use case 'add' has two bindings with id 'b'")
  }

  @Test
  func `two bindings of a route with one id make it INVALID`() throws {
    let route = DefinitionSamples.route.setting(
      "bindings",
      bindings([DefinitionSamples.binding(id: "t"), DefinitionSamples.binding(id: "t")]),
    )
    let found = try check(
      DefinitionSamples.useCase
        .setting("id", #""add""#)
        .setting("validation", "[\(route.json)]"),
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .duplicateBinding)
    #expect(
      found.first?.message
        == "validation route 'unit-tests' of use case 'add' has two bindings with id 't'",
    )
  }

  @Test
  func `one binding id in the use case and in a route, or in two routes, is no duplicate`() throws {
    let first = DefinitionSamples.route(id: "first", covers: ["valid-credentials"])
      .setting("bindings", bindings([DefinitionSamples.binding(id: "same")]))
    let second = DefinitionSamples.route(id: "second", covers: ["valid-credentials"])
      .setting("bindings", bindings([DefinitionSamples.binding(id: "same")]))
    let found = try check(
      DefinitionSamples.useCase
        .setting("bindings", bindings([DefinitionSamples.binding(id: "same")]))
        .setting("validation", "[\(first.json),\(second.json)]"),
    )

    #expect(found.isEmpty)
  }

  @Test(
    arguments: [
      (#"{"line":9}"#, #"{"line":3}"#),
      (#"{"line":5,"column":8}"#, #"{"line":5,"column":2}"#),
      (#"{"line":5,"column":4}"#, #"{"line":5,"column":2}"#),
      (#"{"line":6,"column":1}"#, #"{"line":5,"column":9}"#),
    ],
  )
  func `a range that starts after it ends makes the use case INVALID`(
    case example: (start: String, end: String),
  ) throws {
    let found = try check(
      DefinitionSamples.useCase.setting(
        "bindings",
        bindings([
          DefinitionSamples.binding(
            id: "legacy",
            start: example.start,
            end: example.end,
          ),
        ]),
      ),
    )

    #expect(found.count == 1)
    #expect(found.first?.code == .malformedRange)
    #expect(found.first?.message.hasPrefix("binding 'legacy' of use case 'authenticate'") == true)
    #expect(found.first?.message.contains("starts after it ends") == true)
  }

  @Test
  func `a range in a route is judged too`() throws {
    let route = DefinitionSamples.route.setting(
      "bindings",
      bindings([
        DefinitionSamples.binding(
          id: "t",
          start: #"{"line":9}"#,
          end: #"{"line":3}"#,
        ),
      ]),
    )
    let found = try check(DefinitionSamples.useCase.setting("validation", "[\(route.json)]"))

    #expect(found.first?.code == .malformedRange)
    #expect(found.first?.message.contains("validation route 'unit-tests'") == true)
  }

  @Test(
    arguments: [
      (#"{"line":3}"#, #"{"line":9}"#),
      (#"{"line":5}"#, #"{"line":5}"#),
      (#"{"line":5,"column":2}"#, #"{"line":5,"column":2}"#),
      (#"{"line":5,"column":3}"#, #"{"line":5,"column":2}"#),
      (#"{"line":5,"column":8}"#, #"{"line":5}"#),
      (#"{"line":5}"#, #"{"line":5,"column":1}"#),
      (#"{"line":5,"column":9}"#, #"{"line":6,"column":1}"#),
    ],
  )
  func `a range that ends where or after it starts is fine`(
    case example: (start: String, end: String),
  ) throws {
    let found = try check(
      DefinitionSamples.useCase.setting(
        "bindings",
        bindings([
          DefinitionSamples.binding(
            id: "legacy",
            start: example.start,
            end: example.end,
          ),
        ]),
      ),
    )

    #expect(found.isEmpty)
  }
}
