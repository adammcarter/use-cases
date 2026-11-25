/// A transformer that turns a test tool's report into one result per validation link.
protocol ResultsTransforming: Sendable {
  func results(for request: ResultsRequest) throws(TransformerFailure) -> ResultsResponse
}
