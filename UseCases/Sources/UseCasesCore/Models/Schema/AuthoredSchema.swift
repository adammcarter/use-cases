/// The four schemas an authored file is checked against (`docs/schemas/authored`).
enum AuthoredSchema: String, CaseIterable, Sendable {
  /// Every `use-cases.yml` scope file.
  case workspace

  /// The use-case definition files under `use_cases_dir`.
  case useCases = "use-cases"

  /// The root `use-case-groups.yml`.
  case useCaseGroups = "use-case-groups"

  /// The optional root `use-cases-bridge.yml`.
  case bridge

  /// The file name of the schema, as it sits in `docs/schemas/authored`.
  var fileName: String {
    "\(rawValue).schema.json"
  }
}
