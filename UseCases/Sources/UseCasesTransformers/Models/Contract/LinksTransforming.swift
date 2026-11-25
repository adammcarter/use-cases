/// A transformer that links code to use cases beyond what markers and manual bindings give.
protocol LinksTransforming: Sendable {
  func links(for request: LinksRequest) throws(TransformerFailure) -> LinksResponse
}
