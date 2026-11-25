/// Authored YAML for the freshness tests: a root with the prefix `app` and one use case,
/// `app.toggle`, with two routes: `manual`, a procedure, and `unit-tests`, which the tests give
/// bindings and resources.
enum FreshnessSamples {
  static let useCase = "app.toggle"

  /// The root's `use-cases.yml`, with the freshness settings and exclusions a test sets.
  static func root(
    bindingIdentity: String? = nil,
    ignore: String? = nil,
    exclude: [String] = [],
  ) -> String {
    var text = "schema_version: 1\nroot: true\nprefix: app\n"

    if bindingIdentity != nil || ignore != nil {
      text += "freshness:\n"
    }

    if let bindingIdentity {
      text += "  binding_identity: \(bindingIdentity)\n"
    }

    if let ignore {
      text += "  normalization:\n    ignore: \(ignore)\n"
    }

    if !exclude.isEmpty {
      text += "discovery:\n  exclude: [\(exclude.joined(separator: ", "))]\n"
    }

    return text
  }

  /// A resource item for `resources`: a file.
  static func file(_ path: String) -> String {
    "- kind: file\n  path: \(path)\n"
  }

  /// A resource item for `resources`: a glob.
  static func glob(_ pattern: String) -> String {
    "- kind: glob\n  pattern: \"\(pattern)\"\n"
  }

  /// The definition file. A DRAFT use case lacks a value tier.
  static func definitions(
    isReady: Bool = true,
    bindings: [String] = [],
    routeBindings: [String] = [],
    resources: [String] = [],
  ) -> String {
    var route = ""

    if !routeBindings.isEmpty {
      route += "        bindings:\n" + indented(routeBindings, by: 10)
    }

    if !resources.isEmpty {
      route += "        resources:\n" + indented(resources, by: 10)
    }

    var text = "use_cases:\n  - id: toggle\n    title: Dark mode\n"

    if isReady {
      text += "    value_tier: core\n"
    }

    text += """
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
              steps: [Check it.]
          - id: unit-tests
            type: { kind: unit }
            covers: [on-state]\n
    """ + route

    if !bindings.isEmpty {
      text += "    bindings:\n" + indented(bindings, by: 6)
    }

    return text
  }

  /// Three use cases in one file: `alpha` and `beta` are READY and each has a route `unit`;
  /// `alpha` has a second scenario that only its route `unit` covers; `gamma` is a DRAFT.
  static func multipleUseCases() -> String {
    """
    use_cases:
      - id: alpha
        title: Alpha
        value_tier: core
        intent: Alpha intent.
        scenarios:
          - id: s1
            when: [a1]
            then: [b1]
          - id: s2
            given: [g2]
            when: [a2]
            then: [b2]
        validation:
          - id: unit
            type: { kind: unit }
            covers: [s1, s2]
          - id: manual
            type: { kind: acceptance }
            covers: [s1]
            procedure:
              steps: [Check alpha.]
      - id: beta
        title: Beta
        value_tier: core
        intent: Beta intent.
        scenarios:
          - id: t1
            when: [c1]
            then: [d1]
        validation:
          - id: unit
            type: { kind: integration }
            covers: [t1]
      - id: gamma
        title: Gamma
        intent: Gamma intent.
        scenarios:
          - id: u1
            when: [e1]
            then: [f1]
        validation:
          - id: unit
            type: { kind: unit }
            covers: [u1]\n
    """
  }

  private static func indented(
    _ items: [String],
    by spaces: Int,
  ) -> String {
    let margin = String(repeating: " ", count: spaces)

    return items
      .flatMap { item in
        item.split(separator: "\n", omittingEmptySubsequences: true)
      }
      .map { line in
        margin + line + "\n"
      }
      .joined()
  }
}
