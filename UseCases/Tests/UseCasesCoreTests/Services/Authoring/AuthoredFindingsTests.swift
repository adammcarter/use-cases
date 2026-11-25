import Testing
@testable import UseCasesCore

struct AuthoredFindingsTests {
  private func findings() throws -> AuthoredFindings {
    try AuthoredFindings(file: workspacePath("use-cases/login.yml"))
  }

  @Test
  func `findings start clean`() throws {
    let findings = try findings()

    #expect(findings.isClean)
    #expect(findings.sorted.isEmpty)
  }

  @Test
  func `an attempt that works gives its value and records nothing`() throws {
    var findings = try findings()

    let value = findings.attempt { () throws(AuthoredShapeError) in
      42
    }

    #expect(value == 42)
    #expect(findings.isClean)
  }

  @Test
  func `an attempt that fails records the problem and gives nil`() throws {
    var findings = try findings()

    let value = findings.attempt { () throws(AuthoredShapeError) -> Int in
      throw .missing(location: "title")
    }

    #expect(value == nil)
    #expect(!findings.isClean)
    #expect(findings.sorted.map(\.message) == ["title: this is required"])
    #expect(findings.sorted.first?.code == .invalidValue)
  }

  @Test
  func `an optional attempt gives nil for an absent value without recording anything`() throws {
    var findings = try findings()

    let value = findings.attemptOptional { () throws(AuthoredShapeError) -> Int? in
      nil
    }

    #expect(value == nil)
    #expect(findings.isClean)
  }

  @Test
  func `findings come back in the order a report shows them`() throws {
    var findings = try findings()
    findings.add(.unknownScenario, "b")
    findings.add(.duplicateRoute, "a")

    #expect(findings.sorted.map(\.code) == [.duplicateRoute, .unknownScenario])
  }

  @Test
  func `diagnostics from elsewhere can be added`() throws {
    var findings = try findings()
    let other = try Diagnostic(
      error: .technicalField,
      in: workspacePath("use-cases/login.yml"),
      message: "x",
    )

    findings.add(contentsOf: [other])

    #expect(findings.sorted == [other])
  }
}
