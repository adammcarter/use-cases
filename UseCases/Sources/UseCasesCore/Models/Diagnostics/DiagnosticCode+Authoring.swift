extension DiagnosticCode {
  /// A value that is not what its field takes: not an id, not a path, not a known choice.
  static let invalidValue: DiagnosticCode = "invalid-value"

  /// A child scope writes a setting only the root may hold.
  static let rootOnlySetting: DiagnosticCode = "root-only-setting"

  /// Two scenarios of one use case share an id.
  static let duplicateScenario: DiagnosticCode = "duplicate-scenario"

  /// Two validation routes of one use case share an id.
  static let duplicateRoute: DiagnosticCode = "duplicate-route"

  /// Two bindings of one use case, or of one route, share an id.
  static let duplicateBinding: DiagnosticCode = "duplicate-binding"

  /// A manual binding's range starts after it ends.
  static let malformedRange: DiagnosticCode = "malformed-range"

  /// A route covers a scenario its use case does not have.
  static let unknownScenario: DiagnosticCode = "unknown-scenario"

  /// A YAML binding says `kind: marker`; markers are found in the code.
  static let markerBindingInYAML: DiagnosticCode = "marker-binding-in-yaml"

  /// A use case or a route names code or tools.
  static let technicalField: DiagnosticCode = "technical-field"
}
