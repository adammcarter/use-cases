import Testing
@testable import UseCasesTransformers

struct JUnitCaseTests {
  private func testCase(
    children: Set<String> = [],
    status: String? = nil,
  ) -> JUnitCase {
    JUnitCase(
      className: "pkg.Suite",
      name: "test_a",
      file: nil,
      line: nil,
      statusAttribute: status,
      children: children,
    )
  }

  @Test(arguments: [
    ([String](), ResultStatus.pass),
    (["failure"], .fail),
    (["error"], .error),
    (["skipped"], .incomplete),
    (["failure", "error"], .fail),
    (["error", "skipped"], .error),
    (["failure", "skipped"], .fail),
    (["flakyFailure"], .pass),
    (["rerunFailure"], .pass),
    (["system-out", "properties"], .pass),
  ])
  func `an element inside the test case decides its result`(
    children: [String],
    expected: ResultStatus,
  ) {
    #expect(testCase(children: Set(children)).status == expected)
  }

  @Test(arguments: [
    ("notrun", ResultStatus.incomplete),
    ("disabled", .incomplete),
    ("run", .pass),
    ("fail", .pass),
  ])
  func `CTest marks tests it did not run by status`(
    status: String,
    expected: ResultStatus,
  ) {
    #expect(testCase(status: status).status == expected)
  }

  @Test
  func `the test id is its class and name`() {
    #expect(testCase().identifier == "pkg.Suite/test_a")
  }
}
