/// Builds the lines of a Swift Testing event stream.
enum SwiftTestingStream {
  static func test(
    _ identifier: String,
    file: String,
    line: Int,
    kind: String = "function",
  ) -> String {
    record(
      kind: "test",
      payload: [
        "kind": kind,
        "id": identifier,
        "sourceLocation": ["_filePath": file, "line": line, "column": 3],
      ],
    )
  }

  static func ended(_ identifier: String) -> String {
    event(
      "testEnded",
      identifier,
    )
  }

  static func skipped(_ identifier: String) -> String {
    event(
      "testSkipped",
      identifier,
    )
  }

  static func issue(
    _ identifier: String?,
    isKnown: Bool,
  ) -> String {
    var payload: [String: Any] = [
      "kind": "issueRecorded",
      "issue": ["isKnown": isKnown],
    ]

    payload["testID"] = identifier

    return record(
      kind: "event",
      payload: payload,
    )
  }

  static func stream(_ lines: String...) -> String {
    lines.joined(separator: "\n") + "\n"
  }

  private static func event(
    _ kind: String,
    _ identifier: String,
  ) -> String {
    record(
      kind: "event",
      payload: ["kind": kind, "testID": identifier],
    )
  }

  private static func record(
    kind: String,
    payload: [String: Any],
  ) -> String {
    jsonLine(["version": 0, "kind": kind, "payload": payload])
  }
}
