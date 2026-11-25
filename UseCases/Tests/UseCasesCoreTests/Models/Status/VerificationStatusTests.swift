import Testing
@testable import UseCasesCore

struct VerificationStatusTests {
  @Test
  func `the cases are listed worst first, then drafts`() {
    #expect(
      VerificationStatus.allCases.map(\.rawValue)
        == ["failed", "error", "incomplete", "unverified", "stale", "verified", "draft"],
    )
  }

  @Test
  func `a worse state has a lower report rank`() {
    let ranks = VerificationStatus.allCases.map(\.reportRank)

    #expect(ranks == Array(0 ..< 7))
  }

  @Test(arguments: [
    (Verdict.pass, VerificationStatus.verified),
    (Verdict.fail, VerificationStatus.failed),
    (Verdict.incomplete, VerificationStatus.incomplete),
    (Verdict.error, VerificationStatus.error),
  ])
  func `a verdict gives a route its state`(
    verdict: Verdict,
    expected: VerificationStatus,
  ) {
    #expect(VerificationStatus(verdict: verdict) == expected)
  }
}
