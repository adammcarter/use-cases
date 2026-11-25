import Testing
@testable import UseCasesTransformers

struct XCTestConsoleTests {
  @Test(arguments: [
    (
      "Test Case '-[ShopTests.LoginTests testValid]' passed (0.001 seconds).",
      "ShopTests" as String?,
      "LoginTests",
      "testValid",
      ResultStatus.pass,
    ),
    (
      "Test Case '-[ShopTests.LoginTests testBad]' failed (0.002 seconds).",
      "ShopTests",
      "LoginTests",
      "testBad",
      .fail,
    ),
    (
      "Test Case '-[ShopTests.LoginTests testSkip]' skipped (0.000 seconds).",
      "ShopTests",
      "LoginTests",
      "testSkip",
      .incomplete,
    ),
    (
      "Test Case 'LoginTests.testValid' passed (0.001 seconds)",
      nil,
      "LoginTests",
      "testValid",
      .pass,
    ),
    (
      "Test Case 'Module.LoginTests.testValid' passed (0.001 seconds)",
      "Module",
      "LoginTests",
      "testValid",
      .pass,
    ),
    ("Test Case '-[LoginTests testValid]' passed", nil, "LoginTests", "testValid", .pass),
    ("Test Case '-[A.B.LoginTests testValid]' passed", "A.B", "LoginTests", "testValid", .pass),
  ])
  func `a result line gives the module, the class, the name and the outcome`(
    line: String,
    moduleName: String?,
    className: String,
    name: String,
    status: ResultStatus,
  ) {
    #expect(
      XCTestConsole(text: line).cases == [
        XCTestResult(
          moduleName: moduleName,
          className: className,
          name: name,
          status: status,
        ),
      ],
    )
  }

  @Test(arguments: [
    "Test Case '-[ShopTests.LoginTests testValid]' started.",
    "Test Suite 'LoginTests' passed at 2026-01-01.",
    "✔ Test valid() passed after 0.001 seconds.",
    "Test Case 'garbled' passed",
    "",
  ])
  func `other console lines are not results`(line: String) {
    #expect(XCTestConsole(text: line).cases.isEmpty)
  }

  @Test
  func `the same class and test name in two modules are two tests`() {
    let console = XCTestConsole(
      text: """
      Test Case '-[ATests.FooTests testA]' failed (0.1 seconds).
      Test Case '-[BTests.FooTests testA]' passed (0.1 seconds).
      """,
    )

    #expect(console.cases.map(\.identifier) == ["ATests.FooTests.testA", "BTests.FooTests.testA"])
    #expect(console.cases.map(\.status) == [.fail, .pass])
  }

  @Test
  func `a case printed again counts by its final attempt within its module`() {
    let console = XCTestConsole(
      text: """
      Test Case '-[A.Foo testOne]' failed (0.1 seconds).
      Test Case '-[B.Foo testOne]' passed (0.1 seconds).
      Test Case '-[A.Foo testOne]' passed (0.1 seconds).
      Test Case '-[A.Foo testTwo]' passed (0.1 seconds).
      Test Case '-[A.Foo testTwo]' failed (0.1 seconds).
      """,
    )

    #expect(
      console.cases.map(\.identifier) == ["A.Foo.testOne", "A.Foo.testTwo", "B.Foo.testOne"],
    )
    #expect(console.cases.map(\.status) == [.pass, .fail, .pass])
  }

  @Test
  func `non-ASCII names are read`() {
    let console = XCTestConsole(text: "Test Case '-[M.C testÄ]' failed (0.1 seconds).\n")

    #expect(console.cases.map(\.name) == ["testÄ"])
  }

  @Test
  func `cases come in id order`() {
    let console = XCTestConsole(
      text: """
      Test Case '-[M.B testA]' passed (0.1 seconds).
      Test Case '-[M.A testZ]' passed (0.1 seconds).
      Test Case '-[M.A testB]' passed (0.1 seconds).
      """,
    )

    #expect(console.cases.map(\.name) == ["testB", "testZ", "testA"])
  }

  @Test
  func `a result survives a line separator inside the output`() {
    let console = XCTestConsole(
      text: "noise \u{2028} more \u{85} noise\nTest Case '-[M.C testX]' failed (0.1 seconds).\n",
    )

    #expect(console.cases.map(\.status) == [.fail])
  }
}
