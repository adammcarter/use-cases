/// Builds the lines of a Cucumber message stream.
enum CucumberStream {
  static func pickle(
    _ identifier: String,
    uri: String,
    name: String,
    line: Int,
  ) -> String {
    jsonLine(
      [
        "pickle": [
          "id": identifier,
          "uri": uri,
          "name": name,
          "location": ["line": line, "column": 3],
          "astNodeIds": ["x"],
        ] as [String: Any],
      ],
    )
  }

  static func testCase(
    _ identifier: String,
    pickle: String,
  ) -> String {
    jsonLine(["testCase": ["id": identifier, "pickleId": pickle]])
  }

  static func started(
    _ identifier: String,
    testCase: String,
    attempt: Int? = nil,
  ) -> String {
    var message: [String: Any] = ["id": identifier, "testCaseId": testCase]

    message["attempt"] = attempt

    return jsonLine(["testCaseStarted": message])
  }

  static func step(
    _ status: String,
    start: String,
    message: String? = nil,
  ) -> String {
    var result: [String: Any] = [
      "status": status,
      "duration": ["seconds": 0, "nanos": 1],
    ]

    result["message"] = message

    return jsonLine(
      [
        "testStepFinished": [
          "testCaseStartedId": start,
          "testStepResult": result,
        ] as [String: Any],
      ],
    )
  }

  /// A scenario that ran once, with the given step statuses.
  static func scenario(
    _ name: String,
    uri: String = "features/a.feature",
    line: Int,
    steps: [String],
  ) -> [String] {
    let start = "s-\(name)"
    let finished = steps.map { status in
      step(
        status,
        start: start,
      )
    }

    return [
      pickle(
        "p-\(name)",
        uri: uri,
        name: name,
        line: line,
      ),
      testCase(
        "c-\(name)",
        pickle: "p-\(name)",
      ),
      started(
        start,
        testCase: "c-\(name)",
      ),
    ] + finished
  }

  static func stream(_ lines: [String]) -> String {
    lines.joined(separator: "\n") + "\n"
  }
}
