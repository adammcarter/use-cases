@testable import UseCasesCore

/// Paths that hide `..` behind a Unicode line separator. ECMA-262 `.` does not cross U+2028 or
/// U+2029, so the "no `..`" check of a path pattern cannot see past one; the pattern has to
/// refuse the separator itself.
enum LineSeparatorSamples {
  static let all: [AuthoredSchemaSample] = [
    .invalid(
      "working_dir hiding .. behind U+2028",
      .bridge,
      bridge(validation: ["working_dir": json("a\u{2028}/../..")]),
    ),
    .invalid(
      "transformer hiding .. behind U+2029",
      .bridge,
      bridge(validation: ["transformer": json("x\u{2029}/../../evil")]),
    ),
    .invalid(
      "link transformer hiding .. behind U+2029",
      .bridge,
      linkBridge(transformer: "x\u{2029}/../../evil"),
    ),
    .invalid(
      "manual binding file hiding .. behind U+2028",
      .useCases,
      useCases(file: "a\u{2028}/../../etc/passwd"),
    ),
    .invalid(
      "resource path hiding .. behind U+2028",
      .useCases,
      useCases(resourcePath: "a\u{2028}/../../etc/passwd"),
    ),
    .invalid(
      "working_dir with a U+2029 and no ..",
      .bridge,
      bridge(validation: ["working_dir": json("a\u{2029}b")]),
    ),
    .valid(
      "working_dir that is a plain folder",
      .bridge,
      bridge(validation: ["working_dir": json("services/auth")]),
    ),
    .valid(
      "manual binding file that is a plain path",
      .useCases,
      useCases(file: "src/a.swift"),
    ),
  ]

  private static func json(_ text: String) -> String {
    "\"" + text + "\""
  }

  private static func bridge(validation changes: KeyValuePairs<String, String>) -> String {
    var validation = JSONMembers([
      "id": json("auth-tests"),
      "transformer": json("swift-testing"),
    ])
    for change in changes {
      validation = validation.setting(change.key, change.value)
    }

    return JSONMembers([
      "schema_version": "1",
      "validations": "[" + validation.json + "]",
    ]).json
  }

  private static func linkBridge(transformer: String) -> String {
    let link = JSONMembers(["transformer": json(transformer)])

    return JSONMembers([
      "schema_version": "1",
      "links": "[" + link.json + "]",
    ]).json
  }

  private static func useCases(
    file: String? = nil,
    resourcePath: String? = nil,
  ) -> String {
    var useCase = JSONMembers([
      "id": json("ui"),
      "title": json("Dark mode"),
    ])
    if let file {
      useCase = useCase.setting("bindings", UseCaseSamples.binding(file: file))
    }
    if let resourcePath {
      let resource = JSONMembers([
        "kind": json("file"),
        "path": json(resourcePath),
      ])
      let route = JSONMembers([
        "id": json("unit-tests"),
        "type": #"{"kind":"unit"}"#,
        "covers": #"["valid-credentials"]"#,
        "resources": "[" + resource.json + "]",
      ])
      useCase = useCase.setting("validation", "[" + route.json + "]")
    }

    return JSONMembers(["use_cases": "[" + useCase.json + "]"]).json
  }
}
