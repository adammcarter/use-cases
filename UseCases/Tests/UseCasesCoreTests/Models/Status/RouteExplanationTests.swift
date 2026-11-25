import Testing
@testable import UseCasesCore

struct RouteExplanationTests {
  private static let run = "0192f0c4e5a17c3e9b04d2f61a8c3b57"

  @Test
  func `a deciding run names the validations that gave the verdict`() {
    let explanation = RouteExplanation.decided(
      run: Self.run,
      via: ["unit-tests", "ui-tests"],
    )

    #expect(
      explanation.text(shortRunIdentifiers: false)
        == "run 0192f0c4e5a17c3e9b04d2f61a8c3b57 via unit-tests, ui-tests",
    )
    #expect(explanation.text(shortRunIdentifiers: true) == "run 0192f0c4 via unit-tests, ui-tests")
  }

  @Test
  func `a deciding run of a newer record version names no source`() {
    let explanation = RouteExplanation.decided(
      run: Self.run,
      via: [],
    )

    #expect(explanation.text(shortRunIdentifiers: true) == "run 0192f0c4")
  }

  @Test
  func `a withheld verdict gives the problem and then the run`() {
    let explanation = RouteExplanation.withheld(
      problem: "its test didn't run",
      run: Self.run,
    )

    #expect(explanation.text(shortRunIdentifiers: true) == "its test didn't run (run 0192f0c4)")
  }

  @Test
  func `a stale route names the run it changed since`() {
    let explanation = RouteExplanation.changedSince(run: Self.run)

    #expect(explanation.text(shortRunIdentifiers: true) == "changed since run 0192f0c4")
    #expect(
      explanation.text(shortRunIdentifiers: false)
        == "changed since run 0192f0c4e5a17c3e9b04d2f61a8c3b57",
    )
  }

  @Test
  func `a route nothing has run for has no verdict yet`() {
    #expect(RouteExplanation.noVerdictYet.text(shortRunIdentifiers: true) == "no verdict yet")
  }
}
