/// `cargo-test`: the console output of `cargo test`, one
/// `test <path> ... ok | FAILED | ignored` line per test.
struct CargoTestTransformer: ResultsTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse {
    let running = #/^\s*Running (?:unittests )?(\S+\.rs) \(/#
    let result = #/^test (\S+) \.\.\. (ok|FAILED|ignored)/#
    let console = try reader.lossyText(at: request.output.reportPath)
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    var locator = CargoTestLocator(
      searcher: SourceSearcher(
        paths: paths,
        reader: reader,
      ),
      listing: SourceFolder(root: paths.root),
      base: request.output.folder,
    )
    var diagnostics: [String] = []
    var located: [LocatedTest] = []
    var target: String?

    for line in console.reportLines {
      if let match = line.prefixMatch(of: running) {
        target = String(match.1)
      } else if let match = line.prefixMatch(of: result) {
        located.append(
          locator.locate(
            path: String(match.1),
            outcome: String(match.2),
            target: target,
            diagnostics: &diagnostics,
          ),
        )
      }
    }

    return LinkAttributor.response(
      links: request.links,
      located: located,
      diagnostics: diagnostics,
    )
  }
}
