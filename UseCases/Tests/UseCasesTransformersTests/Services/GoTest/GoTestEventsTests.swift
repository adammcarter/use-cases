import Testing
@testable import UseCasesTransformers

struct GoTestEventsTests {
  private func event(
    _ action: String,
    _ test: String?,
    package: String = "m/p",
  ) -> String {
    GoTestStream.event(
      action,
      test,
      package: package,
    )
  }

  private func statuses(_ lines: String...) -> [GoTestEvents.Test: [ResultStatus]] {
    GoTestEvents(text: lines.joined(separator: "\n")).statuses
  }

  @Test(arguments: [("pass", ResultStatus.pass), ("fail", .fail), ("skip", .incomplete)])
  func `a test's final action is its result`(
    action: String,
    expected: ResultStatus,
  ) {
    #expect(statuses(event(
      action,
      "TestA",
    )) == [.init(package: "m/p", name: "TestA"): [expected]])
  }

  @Test
  func `subtests roll up into their top-level test`() {
    let result = statuses(
      event(
        "pass",
        "TestA/one",
      ),
      event(
        "fail",
        "TestA/two",
      ),
      event(
        "fail",
        "TestA",
      ),
    )

    #expect(result.count == 1)
    #expect(result[.init(package: "m/p", name: "TestA")] == [.pass, .fail, .fail])
  }

  @Test
  func `events that are not a test's end are ignored`() {
    let result = statuses(
      event(
        "run",
        "TestA",
      ),
      event(
        "output",
        "TestA",
      ),
      event(
        "pause",
        "TestA",
      ),
      event(
        "pass",
        nil,
      ),
      event(
        "fail",
        nil,
      ),
    )

    #expect(result.isEmpty)
  }

  @Test
  func `build errors printed as plain text are skipped`() {
    let result = statuses(
      "# m/p [build failed]",
      "./a.go:3:1: syntax error",
      "",
      event(
        "pass",
        "TestA",
      ),
    )

    #expect(result.count == 1)
  }

  @Test
  func `the same test name in two packages is two tests`() {
    let result = statuses(
      event(
        "pass",
        "TestA",
        package: "m/p",
      ),
      event(
        "fail",
        "TestA",
        package: "m/q",
      ),
    )

    #expect(result.count == 2)
  }
}
