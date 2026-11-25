/// The two jobs a transformer does (chapter 10 §10). The job is the argument a transformer is
/// started with, and the `job` its request carries.
enum TransformerJob: String, Sendable {
  /// Which code each use case depends on, beyond markers and manual bindings (chapter 10 §11).
  case links

  /// A result for every validation link, from a test tool's report (chapter 10 §13).
  case results
}
