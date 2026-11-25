/// `swift-testing`: one result per validation link from Swift Testing's event stream.
struct SwiftTestingTransformer: ResultsTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let report = request.output.reportPath

    guard reader.exists(at: report) else {
      return LinkAttributor.response(
        links: request.links,
        located: [],
        diagnostics: ["no report was written, so no test results are available"],
      )
    }

    let events = try SwiftTestingEvents(
      text: reader.text(at: report),
      path: report,
    )
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    let diagnostics = events.issuesOutsideTests > 0
      ? ["\(events.issuesOutsideTests) issue(s) recorded outside any test"]
      : []

    return LinkAttributor.response(
      links: request.links,
      located: events.located(paths: paths),
      diagnostics: diagnostics,
    )
  }
}
