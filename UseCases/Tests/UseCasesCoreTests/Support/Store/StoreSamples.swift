/// Documents of the results store, written as the chapters and `validate.py` write them. Tests
/// change one member at a time to break them.
enum StoreSamples {
  static let runIdentifier = "0000000000000000000000000000002a"
  static let timestamp = "2026-09-25T12:34:56.123Z"
  static let fingerprint = "uc-route-v1-sha256:" + String(repeating: "a", count: 64)
  static let otherFingerprint = "uc-route-v1-sha256:" + String(repeating: "b", count: 64)
  static let useCase = "shop.login.authenticate"
  static let route = "unit-tests"
  static let linkKey =
    "shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6"
  static let otherLinkKey =
    "shop.login.authenticate#unit-tests.other@Tests/AuthTests/LoginTests.swift:13"

  static func digest(_ character: Character) -> String {
    String(repeating: character, count: 64)
  }

  static func quoted(_ text: String) -> String {
    "\"\(text)\""
  }

  /// A source that ran its own command, as `verify --run` records it.
  static var source: JSONMembers {
    JSONMembers([
      "id": quoted("auth-tests"),
      "report": quoted("reports/auth-tests/auth-tests.jsonl"),
      "transformer": quoted("swift-testing"),
      "command": #"["swift","test"]"#,
      "exit_code": "1",
      "seconds": "1.7",
      "diagnostics": #"["2 tests had no source line"]"#,
    ])
  }

  static func manifest(
    runIdentifier: String = runIdentifier,
    kind: String = "verify",
    sources: String? = nil,
  ) -> JSONMembers {
    JSONMembers([
      "run_version": "1",
      "run_id": quoted(runIdentifier),
      "created_at": quoted(timestamp),
      "kind": quoted(kind),
      "sources": sources ?? (kind == "record" ? "[]" : "[\(source.json)]"),
      "errors": "[]",
      "diagnostics": "[\(diagnostic.json)]",
      "unlinked_tests": "[\(unlinkedTest.json)]",
      "notes": "[]",
    ])
  }

  static var diagnostic: JSONMembers {
    JSONMembers([
      "problem": quoted("its test didn't run"),
      "use_case": quoted("shop.login.remember-me"),
      "route": quoted(route),
      "fingerprint": quoted(fingerprint),
      "links": "[\(quoted(linkKey))]",
    ])
  }

  static var unlinkedTest: JSONMembers {
    JSONMembers([
      "test": quoted("AuthTests.LoginTests/notTiedToAnyUseCase()"),
      "file": quoted("Tests/AuthTests/LoginTests.swift"),
      "line": "35",
      "status": quoted("pass"),
    ])
  }

  /// A verdict from a verify run.
  static func result(
    useCase: String = useCase,
    route: String = route,
    fingerprint: String = fingerprint,
    status: String = "pass",
  ) -> JSONMembers {
    JSONMembers([
      "record_version": "1",
      "use_case": quoted(useCase),
      "route": quoted(route),
      "fingerprint": quoted(fingerprint),
      "status": quoted(status),
      "links": JSONMembers([
        linkKey: quoted(status),
        otherLinkKey: "null",
      ]).json,
      "via": #"["auth-tests"]"#,
      "recorded_at": quoted(timestamp),
    ])
  }

  /// A verdict from `use-cases record`.
  static func recordedResult(
    useCase: String = useCase,
    route: String = route,
    fingerprint: String = fingerprint,
    status: String = "pass",
  ) -> JSONMembers {
    JSONMembers([
      "record_version": "1",
      "use_case": quoted(useCase),
      "route": quoted(route),
      "fingerprint": quoted(fingerprint),
      "status": quoted(status),
      "via": #"["record"]"#,
      "recorded_at": quoted(timestamp),
      "message": quoted("checked by hand"),
    ])
  }

  static func completion(
    runIdentifier: String = runIdentifier,
    resultCount: Int = 1,
    manifestDigest: String = digest("a"),
    resultsDigest: String = digest("b"),
  ) -> JSONMembers {
    JSONMembers([
      "completion_version": "1",
      "run_id": quoted(runIdentifier),
      "finished_at": quoted(timestamp),
      "termination": quoted("completed"),
      "result_count": String(resultCount),
      "manifest_sha256": quoted(manifestDigest),
      "results_sha256": quoted(resultsDigest),
      "outputs_sha256": JSONMembers(["auth-tests/console.txt": quoted(digest("d"))]).json,
      "reports_sha256": JSONMembers(["auth-tests/auth-tests.jsonl": quoted(digest("c"))]).json,
    ])
  }

  static var start: JSONMembers {
    JSONMembers([
      "start_version": "1",
      "run_id": quoted(runIdentifier),
      "started_at": quoted(timestamp),
      "opened_by": quoted("start"),
      "selected": #"["auth-tests"]"#,
      "validations_sha256": quoted(digest("9")),
      "routes": "[\(startRoute.json)]",
      "files": JSONMembers(["Tests/AuthTests/LoginTests.swift": quoted(digest("f"))]).json,
    ])
  }

  private static var startRoute: JSONMembers {
    JSONMembers([
      "use_case": quoted(useCase),
      "route": quoted(route),
      "fingerprint": quoted(fingerprint),
    ])
  }

  static var runOrder: JSONMembers {
    JSONMembers([
      "order_version": "1",
      "last_run_id": quoted(runIdentifier),
    ])
  }
}
