/// Makes the private place a transformer's request and response live in (chapter 10 §10).
protocol TransformerScratchMaking: Sendable {
  /// A new folder only this user can enter, outside the workspace and `.use-cases/`.
  func makeScratch() throws(TransformerScratchError) -> TransformerScratch
}
