/// The root's freshness policy with its defaults filled in (chapter 04, chapter 09 §23).
struct FreshnessPolicy: Equatable, Sendable {
  /// What an omitted `freshness` means: `content`, with line endings ignored (chapter 11 §12).
  static let standard = FreshnessPolicy(
    bindingIdentity: .content,
    ignoring: [.lineEndings],
  )

  let bindingIdentity: BindingIdentityMode

  /// The differences content comparison ignores, each once, line endings before whitespace
  /// (chapter 11 §89.7), however they were written.
  let ignoring: [FreshnessNormalization]

  init(
    bindingIdentity: BindingIdentityMode,
    ignoring: [FreshnessNormalization],
  ) {
    self.bindingIdentity = bindingIdentity
    self.ignoring = FreshnessNormalization.allCases.filter { rule in
      ignoring.contains(rule)
    }
  }

  /// Reads the `freshness` mapping. An omitted `normalization` or `ignore` ignores line endings;
  /// a written `ignore: []` ignores nothing.
  init(authored object: AuthoredObject) throws(AuthoredShapeError) {
    let mode = try object.optionalChoice(
      "binding_identity",
      as: BindingIdentityMode.self,
    )

    var ignoring = Self.standard.ignoring

    if let normalization = try object.optionalObject("normalization"),
       normalization.contains("ignore")
    {
      ignoring = []

      for (index, text) in try normalization.strings("ignore").enumerated() {
        guard let rule = FreshnessNormalization(rawValue: text) else {
          throw .unknownChoice(
            location: "\(normalization.location(of: "ignore"))[\(index)]",
            text: text,
          )
        }

        ignoring.append(rule)
      }
    }

    self.init(
      bindingIdentity: mode ?? .content,
      ignoring: ignoring,
    )
  }
}
