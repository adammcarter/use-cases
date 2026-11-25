/// Authored YAML for the loading tests: the files a workspace on disk holds.
enum YAMLSamples {
  /// A root scope with the prefix `app`.
  static let root = "schema_version: 1\nroot: true\nprefix: app\n"

  /// A child scope with a prefix.
  static func child(prefix: String) -> String {
    "schema_version: 1\nprefix: \(prefix)\n"
  }

  /// One READY use case, written as an item of `use_cases`.
  static func useCase(
    _ local: String = "toggle",
    title: String = "Dark mode",
    extra: String = "",
  ) -> String {
    """
      - id: \(local)
        title: \(title)
        value_tier: core
        intent: Readable at night.
        scenarios:
          - id: on-state
            when: [x]
            then: [y]
        validation:
          - id: manual
            type: { kind: acceptance }
            covers: [on-state]
            procedure:
              steps: [Check it.]\n
    """ + extra
  }

  /// A definition file with an optional prefix and these use cases.
  static func file(
    prefix: String? = nil,
    _ useCases: String...,
  ) -> String {
    let header = prefix.map { prefix in
      "prefix: \(prefix)\n"
    } ?? ""

    return header + "use_cases:\n" + useCases.joined()
  }
}
