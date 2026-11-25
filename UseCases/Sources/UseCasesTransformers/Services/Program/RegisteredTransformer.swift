/// A bundled transformer, with the one job it does.
enum RegisteredTransformer: Sendable {
  case results(any ResultsTransforming)
  case links(any LinksTransforming)

  var job: TransformerJob {
    switch self {
    case .results: .results
    case .links: .links
    }
  }
}
