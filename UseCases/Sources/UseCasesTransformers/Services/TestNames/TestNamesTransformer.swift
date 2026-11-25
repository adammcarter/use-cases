/// `test-names`: links tests to use cases by naming convention instead of markers. Each match of
/// the `pattern` setting in a file of the `files` setting becomes one link.
struct TestNamesTransformer: LinksTransforming {
  private let reader: any ReportReading

  init(reader: any ReportReading = ReportFile()) {
    self.reader = reader
  }

  func links(for request: LinksRequest) throws(TransformerFailure) -> LinksResponse {
    let settings = try TestNamesSettings(settings: request.settings)
    let paths = WorkspacePaths(codeRoot: request.codeRoot)
    var scan = TestNamesScan(
      settings: settings,
      useCases: request.useCases,
      paths: paths,
      reader: reader,
    )

    let files = SourceFolder(root: paths.root).files(
      matching: settings.files,
      under: "",
    )

    for file in files {
      try scan.scan(file: file)
    }

    return LinksResponse(
      links: scan.links,
      diagnostics: scan.diagnostics,
    )
  }
}
