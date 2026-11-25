/// The schemas the results store is checked against (`docs/schemas/engine`). Each refers to
/// the definitions of `common.schema.json`, which is bundled with them.
enum StoreSchema: String, CaseIterable, Sendable {
  /// `run.json`
  case run

  /// One line of `results.jsonl`.
  case result

  /// `completion.json`
  case completion

  /// `start.json`
  case start

  /// `run-order.json`
  case runOrder = "run-order"

  /// The shared definitions the others refer to, by this file name.
  static let commonFileName = "common.schema.json"

  /// The file name of the schema, as it sits in `docs/schemas/engine`.
  var fileName: String {
    "\(rawValue).schema.json"
  }
}
