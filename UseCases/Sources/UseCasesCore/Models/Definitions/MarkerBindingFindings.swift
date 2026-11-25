/// The YAML bindings that say `kind: marker`, found in a definition file as written (chapter 08
/// "Marker identity", chapter 09 §20.1).
struct MarkerBindingFindings: Equatable, Sendable {
  /// One problem for each such binding, in its own words.
  var diagnostics: [Diagnostic] = []

  /// Where each such binding sits in the document.
  var bindingPaths: [[SchemaPathStep]] = []

  /// Whether the schema's complaint is about one of these bindings, which the problem for the
  /// binding already covers.
  func covers(_ failure: SchemaFailure) -> Bool {
    bindingPaths.contains { path in
      failure.path.starts(with: path)
    }
  }
}
