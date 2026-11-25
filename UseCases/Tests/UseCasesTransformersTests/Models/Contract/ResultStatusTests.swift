import Testing
@testable import UseCasesTransformers

struct ResultStatusTests {
  @Test(arguments: [
    ([ResultStatus.pass, .fail], ResultStatus.fail),
    ([.pass, .error], .error),
    ([.pass, .incomplete], .incomplete),
    ([.incomplete, .error], .error),
    ([.error, .fail, .incomplete], .fail),
    ([.pass, .pass], .pass),
    ([.incomplete], .incomplete),
  ])
  func `the worst of several is fail, then error, then incomplete, then pass`(
    statuses: [ResultStatus],
    expected: ResultStatus,
  ) {
    #expect(ResultStatus.worst(of: statuses) == expected)
  }

  @Test
  func `no statuses have no worst`() {
    #expect(ResultStatus.worst(of: []) == nil)
  }

  @Test(arguments: ["pass", "fail", "error", "incomplete"])
  func `each of the four names is spelled as the contract spells it`(name: String) {
    #expect(ResultStatus(rawValue: name)?.rawValue == name)
  }

  @Test(arguments: ["passed", "skipped", "PASS", ""])
  func `no other name is a status`(name: String) {
    #expect(ResultStatus(rawValue: name) == nil)
  }
}
