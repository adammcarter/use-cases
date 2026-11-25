/// Reads source files for test names that name a use case, collecting the links they make and the
/// names that match nothing.
struct TestNamesScan {
  private(set) var links: [ProducedLink] = []
  private(set) var diagnostics: [String] = []
  private let settings: TestNamesSettings
  private let routesOfUseCase: [String: Set<String>]
  private let paths: any PathResolving
  private let reader: any ReportReading

  init(
    settings: TestNamesSettings,
    useCases: [UseCaseReference],
    paths: any PathResolving,
    reader: any ReportReading,
  ) {
    self.settings = settings
    self.paths = paths
    self.reader = reader
    routesOfUseCase = Dictionary(
      useCases.map { useCase in
        (useCase.id, Set(useCase.routes.map(\.id)))
      },
      uniquingKeysWith: { first, _ in first },
    )
  }

  /// Links every test name written in `file`, a workspace-relative path.
  mutating func scan(file: String) throws(TransformerFailure) {
    guard let text = reader.sourceText(at: paths.absolute(file)) else {
      diagnostics.append("\(file): not UTF-8 text; skipped")

      return
    }

    let lines = text.sourceLines

    for (index, line) in lines.enumerated() {
      for match in line.matches(of: settings.pattern) {
        guard let name = match.output["id"]?.substring else {
          throw .settingInvalid(
            name: "pattern",
            expected: "a regular expression with a named group `id`",
          )
        }

        link(
          name: String(name),
          at: LinkPlace(
            file: file,
            lines: lines,
            index: index,
            column: line.unicodeScalars.distance(
              from: line.unicodeScalars.startIndex,
              to: match.range.lowerBound,
            ),
          ),
        )
      }
    }
  }

  /// Where a test name was found: the lines of its file, the 0-based line, and the scalar offset
  /// of the match in that line.
  private struct LinkPlace {
    let file: String
    let lines: [String]
    let index: Int
    let column: Int
  }

  private mutating func link(
    name: String,
    at place: LinkPlace,
  ) {
    let spot = "\(place.file):\(place.index + 1)"

    guard let identifier = MarkerIdentifier(name),
          let routes = routesOfUseCase[identifier.useCase]
    else {
      diagnostics.append("\(spot): '\(name)' names no known use case")

      return
    }

    if let route = identifier.route, !routes.contains(route) {
      diagnostics.append("\(spot): '\(name)' names no known route")

      return
    }

    let last = settings.block.lastLine(
      in: place.lines,
      from: place.index,
      column: place.column,
    )

    links.append(
      ProducedLink(
        useCase: identifier.useCase,
        route: identifier.route,
        binding: identifier.binding,
        role: identifier.route == nil ? .implementation : .validation,
        file: place.file,
        range: LineRange(
          start: place.index + 1,
          end: last + 1,
        ),
      ),
    )
  }
}
