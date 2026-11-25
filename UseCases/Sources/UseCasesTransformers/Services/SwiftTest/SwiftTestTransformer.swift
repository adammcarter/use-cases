/// `swift-test`: Swift Testing from `events.jsonl` and XCTest from `console.txt`, both in the
/// report folder.
struct SwiftTestTransformer: ResultsTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    let report = request.output.reportPath
    var located: [LocatedTest] = []
    var diagnostics: [String] = []

    let eventsPath = report + "/events.jsonl"
    if reader.exists(at: eventsPath) {
      let events = try SwiftTestingEvents(
        text: reader.text(at: eventsPath),
        path: eventsPath,
      )

      located += events.located(paths: paths)

      if events.issuesOutsideTests > 0 {
        diagnostics.append("\(events.issuesOutsideTests) issue(s) recorded outside any test")
      }
    } else {
      diagnostics.append("no events.jsonl in the report: Swift Testing results unavailable")
    }

    let consolePath = report + "/console.txt"
    if reader.exists(at: consolePath) {
      let console = try XCTestConsole(text: reader.lossyText(at: consolePath))
      var locator = XCTestLocator(
        searcher: SourceSearcher(
          paths: paths,
          reader: reader,
        ),
        listing: SourceFolder(root: paths.root),
        base: request.output.folder,
      )

      located += console.cases.map { testCase in
        locator.locate(
          testCase,
          diagnostics: &diagnostics,
        )
      }
    } else {
      diagnostics.append("no console.txt in the report: XCTest results unavailable")
    }

    return LinkAttributor.response(
      links: request.links,
      located: located,
      diagnostics: diagnostics,
    )
  }
}
