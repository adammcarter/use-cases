import Testing
@testable import UseCasesCore

struct RouteExplanationTests {
  private static let run = "0192f0c4e5a17c3e9b04d2f61a8c3b57"
  private static let shortener = RunIdentifierShortener(runs: [run])
  private static let sameMinute = "0192f0c4e5b27c3e9b04d2f61a8c3b58"
  private static let sameMinuteShortener = RunIdentifierShortener(runs: [run, sameMinute])

  @Test
  func `a deciding run names the validations that gave the verdict`() {
    let explanation = RouteExplanation.decided(
      run: Self.run,
      via: ["unit-tests", "ui-tests"],
    )

    #expect(
      explanation.text(shortening: nil)
        == "run 0192f0c4e5a17c3e9b04d2f61a8c3b57 via unit-tests, ui-tests",
    )
    #expect(explanation.text(shortening: Self.shortener) == "run 0192f0c4 via unit-tests, ui-tests")
  }

  @Test
  func `two runs that share their first 8 digits are told apart by a longer prefix`() {
    let first = RouteExplanation.decided(run: Self.run, via: ["acceptance"])
    let second = RouteExplanation.decided(run: Self.sameMinute, via: ["acceptance"])

    #expect(first.text(shortening: Self.sameMinuteShortener) == "run 0192f0c4e5a via acceptance")
    #expect(second.text(shortening: Self.sameMinuteShortener) == "run 0192f0c4e5b via acceptance")
  }

  @Test
  func `a withheld verdict and a changed route tell two close runs apart`() {
    #expect(
      RouteExplanation.withheld(problem: "its test didn't run", run: Self.run)
        .text(shortening: Self.sameMinuteShortener) == "its test didn't run (run 0192f0c4e5a)",
    )
    #expect(
      RouteExplanation.changedSince(run: Self.sameMinute, lastResult: "pass")
        .text(shortening: Self.sameMinuteShortener)
        == "changed since run 0192f0c4e5b (last result: pass)",
    )
  }

  // @use-case:status.detail#swift-tests.stale-keeps-last-result
  @Test
  func `a stale route a run gave no verdict says why, then what it changed since`() {
    let explanation = RouteExplanation.withheldSinceChange(
      problem: "its test didn't run",
      run: Self.sameMinute,
      changedSince: Self.run,
      lastResult: "fail",
    )

    #expect(
      explanation.text(shortening: Self.sameMinuteShortener)
        == "its test didn't run (run 0192f0c4e5b) · changed since run 0192f0c4e5a"
        + " (last result: fail)",
    )
    #expect(
      explanation.text(shortening: nil)
        == "its test didn't run (run 0192f0c4e5b27c3e9b04d2f61a8c3b58)"
        + " · changed since run 0192f0c4e5a17c3e9b04d2f61a8c3b57 (last result: fail)",
    )
  }

  // @use-case:end status.detail#swift-tests.stale-keeps-last-result

  @Test
  func `a lone run keeps its first 8 digits among runs that differ earlier`() {
    let shortener = RunIdentifierShortener(runs: [Self.run, "0192f0c5e5a17c3e9b04d2f61a8c3b57"])

    #expect(
      RouteExplanation.changedSince(run: Self.run, lastResult: "fail").text(shortening: shortener)
        == "changed since run 0192f0c4 (last result: fail)",
    )
  }

  @Test
  func `a deciding run of a newer record version names no source`() {
    let explanation = RouteExplanation.decided(
      run: Self.run,
      via: [],
    )

    #expect(explanation.text(shortening: Self.shortener) == "run 0192f0c4")
  }

  @Test
  func `a withheld verdict gives the problem and then the run`() {
    let explanation = RouteExplanation.withheld(
      problem: "its test didn't run",
      run: Self.run,
    )

    #expect(explanation.text(shortening: Self.shortener) == "its test didn't run (run 0192f0c4)")
  }

  @Test
  func `a stale route names the run it changed since`() {
    let explanation = RouteExplanation.changedSince(run: Self.run, lastResult: "error")

    #expect(
      explanation.text(shortening: Self.shortener)
        == "changed since run 0192f0c4 (last result: error)",
    )
    #expect(
      explanation.text(shortening: nil)
        == "changed since run 0192f0c4e5a17c3e9b04d2f61a8c3b57 (last result: error)",
    )
  }

  @Test
  func `a route nothing has run for has no verdict yet`() {
    #expect(RouteExplanation.noVerdictYet.text(shortening: Self.shortener) == "no verdict yet")
  }
}
