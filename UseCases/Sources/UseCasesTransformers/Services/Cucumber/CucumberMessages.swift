/// Cucumber's message stream (`--format message:<file>`): NDJSON, one envelope per line.
struct CucumberMessages: Equatable, Sendable {
  private var pickles: [String: CucumberPickle] = [:]
  private var pickleOfTestCase: [String: String] = [:]
  private var starts: [CucumberStart] = []
  private var stepsOfStart: [String: [ResultStatus]] = [:]
  /// One note for each line that is not a message.
  private(set) var diagnostics: [String] = []

  init(text: String) {
    for line in JSONLines(text: text).lines {
      guard let envelope = line.value else {
        diagnostics.append("line \(line.number) is not a message; ignored")

        continue
      }

      let isMessage = apply(
        envelope,
        line: line.number,
      )

      if !isMessage {
        diagnostics.append("line \(line.number) is not a message; ignored")
      }
    }
  }

  /// Each scenario that ran, by its last attempt, in file and line order.
  var scenarios: [CucumberScenario] {
    var last: [String: (attempt: Int, start: String)] = [:]

    for start in starts {
      guard let pickle = pickleOfTestCase[start.testCase] else {
        continue
      }

      if start.attempt >= (last[pickle]?.attempt ?? -1) {
        last[pickle] = (start.attempt, start.identifier)
      }
    }

    return last.compactMap { pickleIdentifier, attempt in
      pickles[pickleIdentifier].map { pickle in
        CucumberScenario(
          pickle: pickle,
          steps: stepsOfStart[attempt.start] ?? [],
        )
      }
    }.sorted { first, second in
      if first.pickle.uri != second.pickle.uri {
        return first.pickle.uri.precedesByCodePoint(second.pickle.uri)
      }

      return first.pickle.line < second.pickle.line
    }
  }

  /// Whether `envelope` was a well-formed message; messages of other kinds are fine and ignored.
  private mutating func apply(
    _ envelope: JSONValue,
    line: Int,
  ) -> Bool {
    if let pickle = envelope["pickle"] {
      return record(
        pickle: pickle,
        line: line,
      )
    }

    if let testCase = envelope["testCase"] {
      return record(testCase: testCase)
    }

    if let started = envelope["testCaseStarted"] {
      return record(started: started)
    }

    if let finished = envelope["testStepFinished"] {
      return record(finished: finished)
    }

    return true
  }

  private mutating func record(
    pickle: JSONValue,
    line number: Int,
  ) -> Bool {
    guard
      let identifier = pickle["id"]?.stringValue,
      let uri = pickle["uri"]?.stringValue,
      let name = pickle["name"]?.stringValue
    else {
      return false
    }

    // Cucumber's schema makes the location optional, but without it a scenario has no line.
    guard let line = pickle["location"]?["line"]?.integerValue else {
      diagnostics.append("line \(number): the scenario '\(name)' has no location; ignored")

      return true
    }

    pickles[identifier] = CucumberPickle(
      uri: uri,
      name: name,
      line: line,
    )

    return true
  }

  private mutating func record(testCase: JSONValue) -> Bool {
    guard let identifier = testCase["id"]?.stringValue,
          let pickle = testCase["pickleId"]?.stringValue
    else {
      return false
    }

    pickleOfTestCase[identifier] = pickle

    return true
  }

  private mutating func record(started: JSONValue) -> Bool {
    guard let identifier = started["id"]?.stringValue,
          let testCase = started["testCaseId"]?.stringValue
    else {
      return false
    }

    starts.append(
      CucumberStart(
        identifier: identifier,
        testCase: testCase,
        attempt: started["attempt"]?.integerValue ?? 0,
      ),
    )

    return true
  }

  private mutating func record(finished: JSONValue) -> Bool {
    guard let start = finished["testCaseStartedId"]?.stringValue,
          let status = finished["testStepResult"]?["status"]?.stringValue
    else {
      return false
    }

    stepsOfStart[start, default: []].append(CucumberMessages.status(of: status))

    return true
  }

  private static func status(of word: String) -> ResultStatus {
    switch word {
    case "PASSED": .pass
    case "FAILED": .fail
    case "AMBIGUOUS": .error
    default: .incomplete
    }
  }
}
