import Testing
@testable import UseCasesCore

struct RouteFingerprintsTests {
  private let routes = [
    LiveRouteFingerprint(useCase: "app.a", route: "one", fingerprint: "uc-route-v1-sha256:1"),
    LiveRouteFingerprint(useCase: "app.a", route: "two", fingerprint: "uc-route-v1-sha256:2"),
    LiveRouteFingerprint(useCase: "app.b", route: "one", fingerprint: "uc-route-v1-sha256:3"),
  ]

  private func problem(_ message: String) throws -> Diagnostic {
    try Diagnostic(
      error: "some-code",
      in: workspacePath("use-cases/a.yml"),
      message: message,
    )
  }

  @Test
  func `without a problem it holds the routes and looks each up by use case and route`() {
    let result = RouteFingerprints(routes: routes, errors: [])

    #expect(!result.isInvalid)
    #expect(result.routes == routes)
    #expect(result.fingerprint(useCase: "app.a", route: "two") == "uc-route-v1-sha256:2")
    #expect(result.fingerprint(useCase: "app.b", route: "one") == "uc-route-v1-sha256:3")
    #expect(result.fingerprint(useCase: "app.b", route: "two") == nil)
  }

  @Test
  func `with a problem it holds no fingerprint at all`() throws {
    let result = try RouteFingerprints(routes: routes, errors: [problem("bad")])

    #expect(result.isInvalid)
    #expect(result.routes.isEmpty)
    #expect(result.fingerprint(useCase: "app.a", route: "one") == nil)
    #expect(result.problems == ["use-cases/a.yml: bad"])
  }

  @Test
  func `problems come in report order, each once`() throws {
    let result = try RouteFingerprints(
      routes: [],
      errors: [problem("b"), problem("a"), problem("b")],
    )

    #expect(result.problems == ["use-cases/a.yml: a", "use-cases/a.yml: b"])
  }

  @Test
  func `warnings come in report order, each once, and never withhold a fingerprint`() throws {
    let result = try RouteFingerprints(
      routes: routes,
      errors: [],
      warnings: [warning("b"), warning("a"), warning("b")],
    )

    #expect(result.routes == routes)
    #expect(result.warningLines == ["use-cases/a.yml: a", "use-cases/a.yml: b"])
  }

  @Test
  func `warnings are kept beside problems`() throws {
    let result = try RouteFingerprints(
      routes: routes,
      errors: [problem("bad")],
      warnings: [warning("careful")],
    )

    #expect(result.problems == ["use-cases/a.yml: bad"])
    #expect(result.warningLines == ["use-cases/a.yml: careful"])
  }

  private func warning(_ message: String) throws -> Diagnostic {
    try Diagnostic(
      file: workspacePath("use-cases/a.yml"),
      position: nil,
      code: "some-code",
      severity: .warning,
      message: message,
    )
  }
}
