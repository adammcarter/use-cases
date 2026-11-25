import Foundation

/// `junit`: JUnit-style XML from one file or a folder of files.
struct JUnitTransformer: ResultsTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let settings = try JUnitSettings(settings: request.settings)
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    var locator = JUnitLocator(
      settings: settings,
      paths: paths,
      workingDirectory: request.output.workingDirectory,
      searcher: SourceSearcher(
        paths: paths,
        reader: reader,
      ),
      listing: SourceFolder(root: paths.root),
    )
    var diagnostics: [String] = []
    let files = reportFiles(at: request.output.reportPath)

    if files.isEmpty {
      diagnostics.append("no JUnit XML found in the report")
    }

    let latest = try finalAttempts(
      in: files,
      locator: &locator,
      diagnostics: &diagnostics,
    )

    let located = latest.map { key, status in
      LocatedTest(
        test: key.identifier,
        file: key.file,
        line: key.line,
        status: status,
      )
    }

    return LinkAttributor.response(
      links: request.links,
      located: located,
      diagnostics: Set(diagnostics).sorted { first, second in
        first.precedesByCodePoint(second)
      },
    )
  }

  /// Each test's result, the same test written again counting by its final attempt (a retry,
  /// chapter 10 §13).
  private func finalAttempts(
    in files: [String],
    locator: inout JUnitLocator,
    diagnostics: inout [String],
  ) throws(TransformerFailure) -> [TestKey: ResultStatus] {
    var latest: [TestKey: ResultStatus] = [:]

    for file in files {
      let report = try JUnitReport(
        data: reader.data(at: file),
        path: file,
      )

      for testCase in report.cases {
        let place = locator.locate(
          testCase,
          diagnostics: &diagnostics,
        )

        latest[
          TestKey(
            identifier: testCase.identifier,
            file: place.file,
            line: place.line,
          ),
        ] = testCase.status
      }
    }

    return latest
  }

  private struct TestKey: Hashable {
    let identifier: String
    let file: String?
    let line: Int?
  }

  /// The report itself, or every `.xml` file under a report folder, in name order.
  private func reportFiles(at path: String) -> [String] {
    guard reader.isFolder(at: path) else {
      return reader.exists(at: path) ? [path] : []
    }

    return reader.files(under: path).filter { file in
      file.hasSuffix(".xml")
    }
  }
}
