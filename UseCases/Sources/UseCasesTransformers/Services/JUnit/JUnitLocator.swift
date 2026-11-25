/// Places a JUnit test case in the source the way the `find` setting says.
struct JUnitLocator {
  private let settings: JUnitSettings
  private let paths: any PathResolving
  private let workingDirectory: String
  private let patternFiles: [String]
  private var searcher: any SourceSearching

  /// `pattern` globs are written from the workspace root; relative paths in the report start at
  /// `workingDirectory`.
  init(
    settings: JUnitSettings,
    paths: any PathResolving,
    workingDirectory: String,
    searcher: any SourceSearching,
    listing: any SourceListing,
  ) {
    self.settings = settings
    self.paths = paths
    self.workingDirectory = workingDirectory
    self.searcher = searcher
    patternFiles = settings.files.map { glob in
      listing.files(
        matching: glob,
        under: "",
      )
    } ?? []
  }

  /// The file and line of `testCase`, both nil when it cannot be placed. Anything that is not
  /// found exactly once is reported in `diagnostics` and left unlinked, never guessed.
  mutating func locate(
    _ testCase: JUnitCase,
    diagnostics: inout [String],
  ) -> (file: String?, line: Int?) {
    switch settings.find {
    case .fileLine:
      locateByLine(
        testCase,
        diagnostics: &diagnostics,
      )
    case .fileName:
      resolve(
        searcher.find(
          needles: ["\"\(testCase.name)\"", "'\(testCase.name)'", "`\(testCase.name)`"],
          in: relativeFile(of: testCase).map { [$0] } ?? [],
        ),
        for: testCase,
        diagnostics: &diagnostics,
      )
    case .pattern:
      resolve(
        searcher.find(
          needles: needles(for: testCase),
          in: candidateFiles(for: testCase),
        ),
        for: testCase,
        diagnostics: &diagnostics,
      )
    }
  }

  private func relativeFile(of testCase: JUnitCase) -> String? {
    guard let file = testCase.file else {
      return nil
    }

    return paths.relativePath(
      of: paths.resolve(
        file,
        in: settings.base ?? workingDirectory,
      ),
    )
  }

  private func locateByLine(
    _ testCase: JUnitCase,
    diagnostics: inout [String],
  ) -> (file: String?, line: Int?) {
    let name = testCase.dottedName

    guard let reportedFile = testCase.file, let text = testCase.line else {
      diagnostics.append("test \(name) has no file and line in the report; left unlinked")

      return (nil, nil)
    }

    guard let file = relativeFile(of: testCase) else {
      diagnostics.append(
        "test \(name) names '\(reportedFile)', outside the workspace; left unlinked",
      )

      return (nil, nil)
    }

    guard let line = Int(text).flatMap(lineNumber(reported:)) else {
      diagnostics.append("test \(name) has line '\(text)', which is no line number; left unlinked")

      return (nil, nil)
    }

    return (file, line)
  }

  /// The 1-based line for a number as the tool counts lines, nil when it is not a line of any
  /// file.
  private func lineNumber(reported: Int) -> Int? {
    guard (-LineRange.largest ... LineRange.largest).contains(reported) else {
      return nil
    }

    let line = reported + 1 - settings.lineBase

    return (1 ... LineRange.largest).contains(line) ? line : nil
  }

  private func needles(for testCase: JUnitCase) -> [String] {
    let method = testCase.name.prefix { character in
      character != "("
    }.trimmingCharacters(in: .whitespaces)

    return settings.patterns.map { pattern in
      pattern
        .replacing(
          "{name}",
          with: testCase.name,
        )
        .replacing(
          "{method}",
          with: method,
        )
    }
  }

  private func candidateFiles(for testCase: JUnitCase) -> [String] {
    guard settings.usesClassFile, !testCase.className.isEmpty else {
      return patternFiles
    }

    let outerClass = testCase.className.split(
      separator: ".",
      omittingEmptySubsequences: false,
    ).last?.split(
      separator: "$",
      omittingEmptySubsequences: false,
    ).first.map(String.init) ?? ""

    return patternFiles.filter { file in
      let name = file.split(separator: "/").last.map(String.init) ?? file
      let stem = name.lastIndex(of: ".").map { dot in
        String(name[..<dot])
      } ?? name

      return stem == outerClass
    }
  }

  private func resolve(
    _ search: DeclarationSearch,
    for testCase: JUnitCase,
    diagnostics: inout [String],
  ) -> (file: String?, line: Int?) {
    switch search {
    case let .found(file, line):
      return (file, line)
    case let .ambiguous(count):
      diagnostics.append(
        "test \(testCase.dottedName) matches \(count) declarations; left unlinked",
      )

      return (nil, nil)
    case .missing:
      diagnostics.append(
        "test \(testCase.dottedName) has no declaration in the source; "
          + "left unlinked",
      )

      return (nil, nil)
    }
  }
}
