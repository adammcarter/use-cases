@testable import UseCasesCore

/// The bridge-settings samples of `docs/schemas/engine/validate.py`, as JSON.
enum BridgeSamples {
  static let all: [AuthoredSchemaSample] = valid + invalid

  private static let validation = JSONMembers([
    "id": #""auth-tests""#,
    "report": #""auth-tests.jsonl""#,
    "transformer": #""swift-testing""#,
    "run": """
    ["swift","test","--experimental-event-stream-output","{report}",\
    "--experimental-event-stream-version","0"]
    """,
  ])

  private static func document(_ validation: JSONMembers) -> String {
    JSONMembers([
      "schema_version": "1",
      "validations": "[\(validation.json)]",
    ]).json
  }

  private static let valid: [AuthoredSchemaSample] = [
    .valid(
      "bridge settings",
      .bridge,
      JSONMembers([
        "schema_version": "1",
        "links": #"[{"transformer":"tools/links.py","settings":{}}]"#,
        "validations": "[\(validation.json)]",
      ]).json,
    ),
    .valid("bridge settings, empty", .bridge, #"{"schema_version":1}"#),
    .valid(
      "bridge validation with working_dir",
      .bridge,
      document(validation.setting("working_dir", #""services/auth""#)),
    ),
    .valid(
      "bridge run argument with a shell brace group",
      .bridge,
      document(validation.setting("run", #"["sh","-c","a || { b; }"]"#)),
    ),
    .valid(
      "bridge run argument with a mistyped placeholder (a core check names it)",
      .bridge,
      document(validation.setting("run", #"["swift","test","{reprot}"]"#)),
    ),
    .valid(
      "bridge validation without run (read-only)",
      .bridge,
      document(validation.removing("run")),
    ),
    .valid(
      "bridge validation without a report name (the tests get the folder)",
      .bridge,
      document(validation.removing("report")),
    ),
  ]

  /// The sample validation with one member changed.
  private struct Change {
    let name: String
    let key: String
    let json: String

    init(
      _ name: String,
      _ key: String,
      _ json: String,
    ) {
      self.name = name
      self.key = key
      self.json = json
    }
  }

  private static let changes: [Change] = [
    Change("report is a path", "report", #"".build/use-cases/auth-tests.jsonl""#),
    Change("report inside .use-cases", "report", #"".use-cases/runs/x.jsonl""#),
    Change("report escapes", "report", #""../x.jsonl""#),
    Change("absolute report", "report", #""/tmp/x.jsonl""#),
    Change("report is ..", "report", #""..""#),
    Change("hidden report name", "report", #"".x""#),
    Change("report name ends in a dot", "report", #""x.""#),
    Change("report name with a space", "report", #""auth tests.jsonl""#),
    Change("report name Windows reserves", "report", #""Con.jsonl""#),
    Change("report name too long", "report", "\"\(String(repeating: "x", count: 65))\""),
    Change("id Windows reserves", "id", #""nul""#),
    Change("bad id", "id", #""Auth_Tests""#),
    Change("zero timeout", "timeout_seconds", "0"),
    Change("working_dir escapes project", "working_dir", #""../elsewhere""#),
    Change("working_dir inside .use-cases", "working_dir", #"".use-cases""#),
    Change("absolute working_dir", "working_dir", #""/tmp""#),
  ]

  private static let invalid: [AuthoredSchemaSample] =
    changes.map { change in
      .invalid(
        change.name,
        .bridge,
        document(validation.setting(change.key, change.json)),
      )
    } + [
      .invalid(
        "missing transformer",
        .bridge,
        document(validation.removing("transformer")),
      ),
    ]
}
