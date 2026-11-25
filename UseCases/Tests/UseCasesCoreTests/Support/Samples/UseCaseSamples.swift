@testable import UseCasesCore

/// The use-case samples of `docs/schemas/engine/validate.py`, as JSON.
enum UseCaseSamples {
  static let all: [AuthoredSchemaSample] = valid + invalid

  private static let route = JSONMembers([
    "id": #""unit-tests""#,
    "type": #"{"kind":"unit"}"#,
    "covers": #"["valid-credentials"]"#,
  ])

  private static let useCase = JSONMembers([
    "id": #""authenticate""#,
    "title": #""Authenticate user""#,
    "value_tier": #""core""#,
    "intent": #""Sign in.""#,
    "scenarios": #"[{"id":"valid-credentials","when":["Submit."],"then":["Signed in."]}]"#,
    "validation": "[\(route.json)]",
  ])

  private static let manual = JSONMembers([
    "id": #""legacy""#,
    "kind": #""manual""#,
    "locator": #"{"file":"src/login.py","start":{"line":40},"end":{"line":78,"column":2}}"#,
  ]).json
  private static let whole =
    #"{"id":"config","kind":"manual","locator":{"file":"config/auth.yml"}}"#

  /// A use case's `bindings` holding one manual binding of a file, the path written as given.
  static func binding(file: String) -> String {
    let locator = JSONMembers(["file": "\"" + file + "\""])
    let binding = JSONMembers([
      "id": #""x""#,
      "kind": #""manual""#,
      "locator": locator.json,
    ])

    return "[" + binding.json + "]"
  }

  private static func document(_ useCase: JSONMembers) -> String {
    JSONMembers([
      "prefix": #""login""#,
      "use_cases": "[\(useCase.json)]",
    ]).json
  }

  private static func document(route: JSONMembers) -> String {
    document(useCase.setting("validation", "[\(route.json)]"))
  }

  private static func approved(
    author: String = "Sam",
    day: String = "2026-10-11",
    behaviour: String? = String(repeating: "a", count: 64),
    note: String? = nil,
  ) -> String {
    var approval = JSONMembers([
      "by": "\"\(author)\"",
      "on": "\"\(day)\"",
    ])
    if let behaviour {
      approval = approval.setting("behaviour", "\"\(behaviour)\"")
    }
    if let note {
      approval = approval.setting("note", "\"\(note)\"")
    }

    return approval.json
  }

  private static let valid: [AuthoredSchemaSample] = [
    .valid(
      "use case, no links",
      .useCases,
      document(useCase),
    ),
    .valid(
      "use case with manual bindings and resources",
      .useCases,
      document(
        useCase
          .setting("bindings", "[\(manual),\(whole)]")
          .setting("validation", "[\(routeWithLinks.json)]"),
      ),
    ),
    .valid(
      "procedure route",
      .useCases,
      document(route: route
        .setting("type", #"{"kind":"acceptance"}"#)
        .setting("gates_verification", "false")
        .setting("procedure", #"{"setup":["Launch."],"steps":["Sign in."],"reset":[]}"#)),
    ),
    .valid(
      "an approved use case",
      .useCases,
      document(useCase.setting("approved", approved(behaviour: shortFingerprint + padding))),
    ),
  ]

  private static let shortFingerprint = "3f9a"
  private static let padding = String(repeating: "0", count: 60)

  private static let routeWithLinks = route
    .setting("bindings", #"[{"id":"t","kind":"manual","locator":{"file":"tests/test_login.py"}}]"#)
    .setting(
      "resources",
      """
      [{"kind":"file","path":"fixtures/users.json"},\
      {"kind":"glob","pattern":"schemas/**/*.json"}]
      """,
    )

  private static let invalid: [AuthoredSchemaSample] = [
    .invalid(
      "runner on a route",
      .useCases,
      document(route: route.setting("runner", #"{"kind":"executable","executable":"swift"}"#)),
    ),
    .invalid(
      "marker binding in YAML",
      .useCases,
      document(useCase.setting("bindings", #"[{"id":"x","kind":"marker"}]"#)),
    ),
    .invalid(
      "procedure with no steps",
      .useCases,
      document(route: route.setting("procedure", #"{"steps":[]}"#)),
    ),
    .invalid(
      "start without end",
      .useCases,
      document(useCase.setting(
        "bindings",
        #"[{"id":"x","kind":"manual","locator":{"file":"a","start":{"line":1}}}]"#,
      )),
    ),
    .invalid(
      "unknown resource kind",
      .useCases,
      document(route: route.setting("resources", #"[{"kind":"url","path":"x"}]"#)),
    ),
    .invalid(
      "absolute binding path",
      .useCases,
      document(useCase.setting(
        "bindings",
        #"[{"id":"x","kind":"manual","locator":{"file":"/etc/passwd"}}]"#,
      )),
    ),
    .invalid(
      "binding path spelled ./",
      .useCases,
      document(useCase.setting("bindings", binding(file: "./src/a.js"))),
    ),
    .invalid(
      "binding path with a trailing /",
      .useCases,
      document(useCase.setting("bindings", binding(file: "src/"))),
    ),
    .invalid(
      "binding path hiding .. behind a line separator",
      .useCases,
      document(useCase.setting("bindings", binding(file: "a\u{2028}/../../etc/passwd"))),
    ),
    .invalid(
      "bad use case id",
      .useCases,
      document(useCase.setting("id", #""Bad_Id""#)),
    ),
    .invalid(
      "an id ending in a line break",
      .useCases,
      document(useCase.setting("id", #""authenticate\n""#)),
    ),
    .invalid(
      "an approval without its fingerprint",
      .useCases,
      document(useCase.setting("approved", approved(behaviour: nil))),
    ),
    .invalid(
      "an approval with a short fingerprint",
      .useCases,
      document(useCase.setting("approved", approved(behaviour: "3f9a"))),
    ),
    .invalid(
      "an approval on no date",
      .useCases,
      document(useCase.setting("approved", approved(day: "yesterday"))),
    ),
    .invalid(
      "an approval with a comment",
      .useCases,
      document(useCase.setting("approved", approved(note: "ok"))),
    ),
  ]
}
