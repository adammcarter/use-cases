/// One `<testcase>` of a JUnit report.
struct JUnitCase: Equatable, Sendable {
  let className: String
  let name: String
  let file: String?
  let line: String?
  /// The `status` attribute some tools write (CTest: `notrun`, `disabled`).
  let statusAttribute: String?
  /// The names of the elements directly inside the test case.
  let children: Set<String>

  /// The test's id: its class and name.
  var identifier: String {
    "\(className)/\(name)"
  }

  /// The test as people name it: its class, a dot, its name.
  var dottedName: String {
    "\(className).\(name)"
  }

  /// `<failure>` fails, `<error>` is an error, `<skipped>` is incomplete (an expected failure is
  /// not a pass), anything else passes. A flaky failure Surefire records inside a passing case
  /// is a pass: the case passed in the end.
  var status: ResultStatus {
    if children.contains("failure") {
      return .fail
    }

    if children.contains("error") {
      return .error
    }

    if children.contains("skipped") || ["notrun", "disabled"].contains(statusAttribute) {
      return .incomplete
    }

    return .pass
  }
}
