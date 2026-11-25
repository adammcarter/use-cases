/// Swift Testing's event stream (`--experimental-event-stream-output`, version 0): one JSON record
/// per line. Reading it never judges anything; it only collects what each test did.
struct SwiftTestingEvents: Equatable, Sendable {
  private(set) var declarations: [String: SwiftTestingDeclaration] = [:]
  private(set) var outcomes: [String: ResultStatus] = [:]
  private(set) var issuesOutsideTests = 0

  /// Reads `text`, the stream written to `path`. A line that is not JSON means the stream is
  /// damaged, so nothing in it can be trusted.
  init(
    text: String,
    path: String,
  ) throws(TransformerFailure) {
    for line in JSONLines(text: text).lines {
      guard let record = line.value else {
        throw .reportMalformed(
          path: path,
          reason: "line \(line.number) is not JSON",
        )
      }

      apply(record)
    }
  }

  /// The tests that finished, placed in the workspace, in id order.
  func located(paths: any PathResolving) -> [LocatedTest] {
    outcomes.keys.sorted { first, second in
      first.precedesByCodePoint(second)
    }.compactMap { identifier in
      // Suites also emit events; only declared test functions are tests.
      guard let declaration = declarations[identifier], let status = outcomes[identifier] else {
        return nil
      }

      return LocatedTest(
        test: identifier,
        file: paths.relativePath(of: declaration.file),
        line: declaration.line,
        status: status,
      )
    }
  }

  private mutating func apply(_ record: JSONValue) {
    guard let payload = record["payload"] else {
      return
    }

    switch record["kind"]?.stringValue {
    case "test":
      recordDeclaration(payload)
    case "event":
      recordEvent(payload)
    default:
      break
    }
  }

  private mutating func recordDeclaration(_ payload: JSONValue) {
    guard payload["kind"]?.stringValue == "function", let identifier = payload["id"]?.stringValue
    else {
      return
    }

    let location = payload["sourceLocation"]

    declarations[identifier] = SwiftTestingDeclaration(
      file: location?["_filePath"]?.stringValue,
      line: location?["line"]?.integerValue,
    )
  }

  private mutating func recordEvent(_ payload: JSONValue) {
    let identifier = payload["testID"]?.stringValue

    switch payload["kind"]?.stringValue {
    case "issueRecorded":
      recordIssue(
        payload,
        in: identifier,
      )
    case "testSkipped":
      if let identifier, outcomes[identifier] == nil {
        outcomes[identifier] = .incomplete
      }
    case "testEnded":
      if let identifier, outcomes[identifier] == nil {
        outcomes[identifier] = .pass
      }
    default:
      break
    }
  }

  private mutating func recordIssue(
    _ payload: JSONValue,
    in identifier: String?,
  ) {
    guard let identifier else {
      issuesOutsideTests += 1

      return
    }

    let isKnown = payload["issue"]?["isKnown"]?.boolValue ?? false

    if !isKnown {
      outcomes[identifier] = .fail
    } else if outcomes[identifier] != .fail {
      // An expected failure is not a pass (chapter 10 §13).
      outcomes[identifier] = .incomplete
    }
  }
}
