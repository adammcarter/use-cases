@testable import UseCasesCore

/// Use-case definition files as JSON, built from the canonical example of chapter 02.
enum DefinitionSamples {
  static let scenario = JSONMembers([
    "id": #""valid-credentials""#,
    "given": #"["The user is signed out."]"#,
    "when": #"["The user submits valid credentials."]"#,
    "then": #"["A session is created.","The dashboard is shown."]"#,
  ])

  static let route = JSONMembers([
    "id": #""unit-tests""#,
    "type": #"{"kind":"unit"}"#,
    "covers": #"["valid-credentials"]"#,
  ])

  /// A READY use case.
  static let useCase = JSONMembers([
    "id": #""authenticate""#,
    "title": #""Authenticate user""#,
    "value_tier": #""core""#,
    "intent": #""Let a valid user in.""#,
    "scenarios": "[\(scenario.json)]",
    "validation": "[\(route.json)]",
  ])

  /// A DRAFT use case: the least that is readable.
  static let draft = JSONMembers([
    "id": #""success""#,
    "title": #""Successful login""#,
  ])

  static func file(
    prefix: String? = nil,
    _ useCases: JSONMembers...,
  ) -> String {
    var members = JSONMembers([:])

    if let prefix {
      members = members.setting("prefix", jsonString(prefix))
    }

    return members
      .setting("use_cases", "[" + useCases.map(\.json).joined(separator: ",") + "]")
      .json
  }

  /// A manual binding of a file, whole or with a range; `start` and `end` are position JSON.
  static func binding(
    id: String,
    start: String? = nil,
    end: String? = nil,
  ) -> JSONMembers {
    var locator = JSONMembers(["file": jsonString("src/login.py")])

    if let start {
      locator = locator.setting("start", start)
    }

    if let end {
      locator = locator.setting("end", end)
    }

    return JSONMembers([
      "id": jsonString(id),
      "kind": jsonString("manual"),
      "locator": locator.json,
    ])
  }

  static func scenario(id: String) -> JSONMembers {
    scenario.setting("id", jsonString(id))
  }

  static func route(
    id: String,
    covers: [String],
  ) -> JSONMembers {
    route
      .setting("id", jsonString(id))
      .setting(
        "covers",
        "[" + covers.map { cover in jsonString(cover) }.joined(separator: ",") + "]",
      )
  }
}
