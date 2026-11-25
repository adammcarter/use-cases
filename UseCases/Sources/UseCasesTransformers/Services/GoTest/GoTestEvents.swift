/// The event stream of `go test -json`. A subtest (`TestX/case`) rolls up into its top-level test.
struct GoTestEvents: Equatable, Sendable {
  struct Test: Hashable, Sendable {
    let package: String
    let name: String
  }

  /// The results of each top-level test and all its subtests.
  private(set) var statuses: [Test: [ResultStatus]] = [:]

  /// Reads `text`. Lines that are not JSON are skipped: `go test` prints build errors as plain
  /// text.
  init(text: String) {
    for line in JSONLines(text: text).lines {
      guard
        let event = line.value,
        let package = event["Package"]?.stringValue,
        let test = event["Test"]?.stringValue,
        let status = GoTestEvents.status(of: event["Action"]?.stringValue)
      else {
        continue
      }

      let top = test.split(
        separator: "/",
        maxSplits: 1,
        omittingEmptySubsequences: false,
      ).first.map(String.init) ?? test

      let key = Test(
        package: package,
        name: top,
      )

      statuses[key, default: []].append(status)
    }
  }

  private static func status(of action: String?) -> ResultStatus? {
    switch action {
    case "pass": .pass
    case "fail": .fail
    case "skip": .incomplete
    default: nil
    }
  }
}
