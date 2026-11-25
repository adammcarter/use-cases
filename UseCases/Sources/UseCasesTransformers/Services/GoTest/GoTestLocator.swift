/// Finds a Go test by its function name: `func TestX(` in the `*_test.go` files of the folder its
/// package maps to.
struct GoTestLocator {
  private var searcher: any SourceSearching
  private let listing: any SourceListing
  private let module: GoModule
  private let base: String

  /// `base` is the folder holding `go.mod`, relative to the code root; "" is the code root.
  init(
    module: GoModule,
    base: String,
    searcher: any SourceSearching,
    listing: any SourceListing,
  ) {
    self.module = module
    self.base = base
    self.searcher = searcher
    self.listing = listing
  }

  mutating func locate(
    _ test: GoTestEvents.Test,
    diagnostics: inout [String],
  ) -> (file: String, line: Int)? {
    guard let directory = module.folder(ofPackage: test.package) else {
      return nil
    }

    let folder = [base, directory].filter { part in
      !part.isEmpty
    }.joined(separator: "/")
    let files = listing.files(directlyIn: folder).filter { file in
      file.hasSuffix("_test.go")
    }

    switch searcher.find(
      needles: ["func \(test.name)("],
      in: files,
    ) {
    case let .found(file, line):
      return (file, line)
    case .ambiguous:
      diagnostics.append("\(test.package).\(test.name) is declared more than once; left unlinked")
      return nil
    case .missing:
      return nil
    }
  }
}
