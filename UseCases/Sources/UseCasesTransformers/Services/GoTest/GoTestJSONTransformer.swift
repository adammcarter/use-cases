/// `go-test-json`: the event stream of `go test -json`. Go names a package and a test, never a file
/// or line, so each top-level test is found by `func TestX(` in its package's `*_test.go` files.
struct GoTestJSONTransformer: ResultsTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    let base = try moduleFolder(of: request)
    let module = try GoModule(
      modFile: paths.absolute(base.isEmpty ? "go.mod" : base + "/go.mod"),
      reader: reader,
    )
    let events = try GoTestEvents(text: reader.text(at: request.output.reportPath))
    var locator = GoTestLocator(
      module: module,
      base: base,
      searcher: SourceSearcher(
        paths: paths,
        reader: reader,
      ),
      listing: SourceFolder(root: paths.root),
    )
    var diagnostics: [String] = []
    var located: [LocatedTest] = []

    for test in events.statuses.keys.sorted(by: GoTestJSONTransformer.inReportOrder) {
      let place = locator.locate(
        test,
        diagnostics: &diagnostics,
      )

      located.append(
        LocatedTest(
          test: "\(test.package).\(test.name)",
          file: place?.file,
          line: place?.line,
          status: ResultStatus.worst(of: events.statuses[test] ?? []) ?? .incomplete,
        ),
      )
    }

    return LinkAttributor.response(
      links: request.links,
      located: located,
      diagnostics: diagnostics,
    )
  }

  /// The folder holding `go.mod`, relative to the code root: the `module` setting, else the
  /// working folder. "" is the code root.
  private func moduleFolder(of request: ResultsRequest) throws(TransformerFailure) -> String {
    guard let setting = try request.settings.string("module") else {
      return request.output.folder
    }

    guard let folder = FolderPath.normalised(setting) else {
      throw .settingInvalid(
        name: "module",
        expected: "a folder inside the workspace",
      )
    }

    return folder
  }

  private static func inReportOrder(
    _ first: GoTestEvents.Test,
    _ second: GoTestEvents.Test,
  ) -> Bool {
    if first.package != second.package {
      return first.package.precedesByCodePoint(second.package)
    }

    return first.name.precedesByCodePoint(second.name)
  }
}
