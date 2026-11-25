/// `cucumber-messages`: Cucumber's message stream. Each scenario, and each example row of an
/// outline, is one test located at its own line in the feature file.
struct CucumberMessagesTransformer: ResultsTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    let base = try request.settings.string("base") ?? request.output.workingDirectory
    let messages = try CucumberMessages(text: reader.text(at: request.output.reportPath))
    let located = messages.scenarios.map { scenario in
      let pickle = scenario.pickle
      let path = paths.resolve(
        pickle.uri,
        in: base,
      )

      return LocatedTest(
        test: "\(pickle.uri):\(pickle.line) \(pickle.name)",
        file: paths.relativePath(of: path),
        line: pickle.line,
        status: scenario.status,
      )
    }

    return LinkAttributor.response(
      links: request.links,
      located: located,
      diagnostics: messages.diagnostics,
    )
  }
}
