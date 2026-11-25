/// Finds a Rust test by its function name: `fn name(`, first in the file of the `Running` line
/// before it, then anywhere under `src/` and `tests/` in the folder the tests ran in.
struct CargoTestLocator {
  private var searcher: any SourceSearching
  private let everywhere: [String]
  private let base: String

  /// `base` is the folder `cargo test` ran in, relative to the code root; "" is the code root.
  /// The paths cargo prints start there.
  init(
    searcher: any SourceSearching,
    listing: any SourceListing,
    base: String,
  ) {
    self.searcher = searcher
    self.base = base
    everywhere = listing.files(
      matching: "src/**/*.rs",
      under: base,
    ) + listing.files(
      matching: "tests/**/*.rs",
      under: base,
    )
  }

  /// `path` is the test's path as cargo prints it (`tests::name`), `target` the source file of
  /// the test binary being run, as cargo prints it.
  mutating func locate(
    path: String,
    outcome: String,
    target: String?,
    diagnostics: inout [String],
  ) -> LocatedTest {
    let name = path.components(separatedBy: "::").last ?? path
    let needles = ["fn \(name)("]
    var search = searcher.find(
      needles: needles,
      in: target.map { file in [inBase(file)] } ?? [],
    )

    if search == .missing {
      search = searcher.find(
        needles: needles,
        in: everywhere,
      )
    }

    var file: String?
    var line: Int?

    switch search {
    case let .found(foundFile, foundLine):
      file = foundFile
      line = foundLine
    case .ambiguous:
      diagnostics.append("test \(path) matches several functions; left unlinked")
    case .missing:
      break
    }

    return LocatedTest(
      test: target.map { binary in "\(binary)::\(path)" } ?? path,
      file: file,
      line: line,
      status: CargoTestLocator.status(of: outcome),
    )
  }

  private func inBase(_ file: String) -> String {
    base.isEmpty ? file : base + "/" + file
  }

  private static func status(of outcome: String) -> ResultStatus {
    switch outcome {
    case "ok": .pass
    case "FAILED": .fail
    default: .incomplete
    }
  }
}
