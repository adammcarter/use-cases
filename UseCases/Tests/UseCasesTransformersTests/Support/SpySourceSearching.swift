@testable import UseCasesTransformers

/// A searcher that reads no source: it notes what it is asked to find, on a stream, and answers
/// as told, each search with the next answer and then with the last again. A copy shares the
/// stream, so the test keeps one to read what the locator asked.
struct SpySourceSearching: SourceSearching {
  /// One search asked for.
  struct Search: Equatable {
    let needles: [String]
    let files: [String]
  }

  /// The searches asked for, in order, until ``asked()``.
  let searches: AsyncStream<Search>

  private let noting: AsyncStream<Search>.Continuation
  private var answers: [DeclarationSearch]
  private let sources: [String: [String]]

  /// - Parameters:
  ///   - answers: What the searches find, one after the other; the last repeats.
  ///   - sources: The lines of the files that `lines(of:)` is asked about; any other file cannot
  ///     be read.
  init(
    answering answers: [DeclarationSearch],
    sources: [String: [String]] = [:],
  ) {
    (searches, noting) = AsyncStream.makeStream(of: Search.self)
    self.answers = answers
    self.sources = sources
  }

  /// Every search asked for so far.
  func asked() async -> [Search] {
    noting.finish()

    var found: [Search] = []

    for await search in searches {
      found.append(search)
    }

    return found
  }

  mutating func find(
    needles: [String],
    in files: [String],
  ) -> DeclarationSearch {
    noting.yield(
      Search(
        needles: needles,
        files: files,
      ),
    )

    return answers.count > 1 ? answers.removeFirst() : answers.first ?? .missing
  }

  mutating func lines(of file: String) -> [String]? {
    sources[file]
  }
}
