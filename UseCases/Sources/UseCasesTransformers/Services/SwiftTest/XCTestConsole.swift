/// The console output of `swift test`, the only place XCTest results appear:
/// `Test Case '-[Module.Class testName]' passed (0.001 seconds).`
struct XCTestConsole: Equatable, Sendable {
  /// One case per module, class and name, in id order. A case printed again counts by its final
  /// attempt (chapter 10 §13).
  let cases: [XCTestResult]

  init(text: String) {
    let result = #/Test Case '-?\[?(?:([\w.]+)\.)?(\w+)[ .](\w+)\]?' (passed|failed|skipped)/#
    var latest: [String: XCTestResult] = [:]

    for line in text.reportLines {
      guard let match = line.firstMatch(of: result) else {
        continue
      }

      let found = XCTestResult(
        moduleName: match.1.map(String.init),
        className: String(match.2),
        name: String(match.3),
        status: XCTestConsole.status(of: match.4),
      )

      latest[found.identifier] = found
    }

    cases = latest.keys.sorted { first, second in
      first.precedesByCodePoint(second)
    }.compactMap { key in
      latest[key]
    }
  }

  private static func status(of word: Substring) -> ResultStatus {
    switch word {
    case "passed": .pass
    case "failed": .fail
    default: .incomplete
    }
  }
}
