import Testing
@testable import UseCasesCore

struct LinkCoverageTests {
  @Test
  func `no links cover nothing`() {
    let coverage = LinkCoverage([])

    #expect(!coverage.hasImplementationLink(useCase: "app.toggle"))
    #expect(
      !coverage.hasValidationLink(
        useCase: "app.toggle",
        route: "manual",
      ),
    )
  }

  @Test
  func `an implementation link covers its use case and no route`() throws {
    let coverage = try LinkCoverage([ResolvedLink.sample()])

    #expect(coverage.hasImplementationLink(useCase: "app.toggle"))
    #expect(!coverage.hasImplementationLink(useCase: "app.other"))
    #expect(
      !coverage.hasValidationLink(
        useCase: "app.toggle",
        route: "manual",
      ),
    )
  }

  @Test
  func `a validation link covers its route and not the use case's code`() throws {
    let coverage = try LinkCoverage([ResolvedLink.sample(route: "manual")])

    #expect(
      coverage.hasValidationLink(
        useCase: "app.toggle",
        route: "manual",
      ),
    )
    #expect(
      !coverage.hasValidationLink(
        useCase: "app.toggle",
        route: "unit-tests",
      ),
    )
    #expect(
      !coverage.hasValidationLink(
        useCase: "app.other",
        route: "manual",
      ),
    )
    #expect(!coverage.hasImplementationLink(useCase: "app.toggle"))
  }
}
