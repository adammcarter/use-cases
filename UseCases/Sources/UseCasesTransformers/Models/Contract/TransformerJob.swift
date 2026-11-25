/// The two jobs a transformer can be asked for (chapter 10 §10).
enum TransformerJob: String, Equatable, Sendable {
  case links
  case results
}
