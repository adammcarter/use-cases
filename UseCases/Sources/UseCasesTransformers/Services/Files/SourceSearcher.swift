/// Finds where a test is declared by looking for its declaration text in source files. Each file
/// is read once.
struct SourceSearcher: SourceSearching {
  private let paths: any PathResolving
  private let reader: any ReportReading
  private var cache: [String: [String]?] = [:]

  init(
    paths: any PathResolving,
    reader: any ReportReading,
  ) {
    self.paths = paths
    self.reader = reader
  }

  mutating func find(
    needles: [String],
    in files: [String],
  ) -> DeclarationSearch {
    var hits: [(file: String, line: Int)] = []

    for file in files {
      guard let lines = lines(of: file) else {
        continue
      }

      for (index, text) in lines.enumerated()
        where needles.contains(where: { needle in text.contains(needle) })
      {
        hits.append((file, index + 1))
      }
    }

    guard let first = hits.first else {
      return .missing
    }

    guard hits.count == 1 else {
      return .ambiguous(count: hits.count)
    }

    return .found(
      file: first.file,
      line: first.line,
    )
  }

  mutating func lines(of file: String) -> [String]? {
    if let known = cache[file] {
      return known
    }

    let loaded = reader.sourceText(at: paths.absolute(file))?.sourceLines

    cache[file] = .some(loaded)

    return loaded
  }
}
