@testable import UseCasesCore

/// Use cases made up at random from a seed, with every field the format has and the texts of
/// ``NastyText`` in them.
struct UseCaseGenerator {
  private static let segments = [
    "on", "no", "yes", "off", "y", "n", "null", "true", "1e3", "0o17", "123", "a", "b-c", "x1",
  ]

  private static let paths = [
    "src/login.py", "src/a #b.swift", "ab: c/d.txt", "docs/[x].md", "it's/here", "日本語/ファイル.md",
    "fixtures/users.json", "-dash/file", "1e3", "on", "a, b/c",
  ]

  private static let patterns = [
    "fixtures/**/*.json", "src/*.swift", "ab: c/**", "x?y", "[x]/*", "on/*",
  ]

  private var generator: SeededGenerator

  init(seed: Int) {
    generator = SeededGenerator(seed: seed)
  }

  mutating func definition() throws -> UseCaseDefinition {
    let scenarioIds = try distinctSegments(upTo: 3).map(ScenarioIdentifier.init(validating:))
    let routeIds = try distinctSegments(upTo: 3).map(RouteIdentifier.init(validating:))

    var routes: [ValidationRoute] = []

    for identifier in routeIds {
      try routes.append(route(
        identifier: identifier,
        scenarios: scenarioIds,
      ))
    }

    var scenarios: [Scenario] = []

    for identifier in scenarioIds {
      scenarios.append(scenario(identifier: identifier))
    }

    return try UseCaseDefinition(
      localIdentifier: IdentifierSegment(validating: segment()),
      title: text(),
      description: flip() ? text() : nil,
      valueTier: flip() ? ValueTier.allCases.randomElement(using: &generator) : nil,
      intent: flip() ? text() : nil,
      outOfScope: texts(),
      scenarios: scenarios,
      routes: routes,
      bindings: bindings(),
      approval: optionalApproval(),
    )
  }

  private mutating func scenario(identifier: ScenarioIdentifier) -> Scenario {
    Scenario(
      identifier: identifier,
      given: texts(),
      when: texts(),
      then: texts(),
    )
  }

  private mutating func route(
    identifier: RouteIdentifier,
    scenarios: [ScenarioIdentifier],
  ) throws -> ValidationRoute {
    let procedure: Procedure? = if flip() {
      Procedure(
        setup: texts(),
        steps: texts(),
        reset: texts(),
      )
    } else {
      nil
    }

    var resources: [RouteResource] = []

    for _ in 0 ..< count(upTo: 2) {
      try resources.append(resource())
    }

    var covers: [ScenarioIdentifier] = []

    for scenario in scenarios where flip() {
      covers.append(scenario)
    }

    return try ValidationRoute(
      identifier: identifier,
      type: type(),
      covers: covers,
      gatesVerification: flip(),
      procedure: procedure,
      bindings: bindings(),
      resources: resources,
    )
  }

  private mutating func resource() throws -> RouteResource {
    if flip() {
      return try .file(WorkspacePath(validating: pick(Self.paths)))
    }

    return try .glob(PathPattern(validating: pick(Self.patterns)))
  }

  private mutating func type() throws -> ValidationType {
    let kinds: [ValidationType] = [
      .unit, .integration, .contract, .snapshot, .userInterface, .e2e, .acceptance, .performance,
    ]

    if Int.random(
      in: 0 ..< 3,
      using: &generator,
    ) == 0 {
      return try .custom(name: IdentifierSegment(validating: segment()))
    }

    return kinds.randomElement(using: &generator) ?? .unit
  }

  private mutating func bindings() throws -> [ManualBinding] {
    var bindings: [ManualBinding] = []

    for (index, name) in distinctSegments(upTo: 2).enumerated() {
      let range: ManualRange? = if flip() {
        try ManualRange(
          start: SourcePosition(
            line: 1 + index,
            column: flip() ? 3 : nil,
          ),
          end: SourcePosition(
            line: 40 + index,
            column: flip() ? 7 : nil,
          ),
        )
      } else {
        nil
      }

      try bindings.append(
        ManualBinding(
          identifier: BindingIdentifier(validating: name),
          locator: ManualLocator(
            file: WorkspacePath(validating: pick(Self.paths)),
            range: range,
          ),
        ),
      )
    }

    return bindings
  }

  private mutating func optionalApproval() -> Approval? {
    guard flip() else {
      return nil
    }

    let year = Int.random(
      in: 2000 ... 2099,
      using: &generator,
    )
    let month = Int.random(
      in: 1 ... 12,
      using: &generator,
    )
    let day = Int.random(
      in: 1 ... 28,
      using: &generator,
    )

    return Approval(
      approver: text(),
      day: "\(year)-\(month < 10 ? "0" : "")\(month)-\(day < 10 ? "0" : "")\(day)",
      behaviour: NastyText.fingerprint(using: &generator),
    )
  }

  private mutating func texts() -> [String] {
    (0 ..< count(upTo: 3)).map { _ in
      text()
    }
  }

  private mutating func text() -> String {
    NastyText.text(using: &generator)
  }

  private mutating func segment() -> String {
    pick(Self.segments)
  }

  private mutating func distinctSegments(upTo most: Int) -> [String] {
    var chosen: [String] = []

    for _ in 0 ..< count(upTo: most) {
      let next = segment()

      if !chosen.contains(next) {
        chosen.append(next)
      }
    }

    return chosen
  }

  private mutating func pick(_ choices: [String]) -> String {
    choices.randomElement(using: &generator) ?? ""
  }

  private mutating func count(upTo most: Int) -> Int {
    Int.random(
      in: 0 ... most,
      using: &generator,
    )
  }

  private mutating func flip() -> Bool {
    Bool.random(using: &generator)
  }
}
