import Testing
import UseCasesCore
@testable import UseCasesCLI

/// The gate's ungated-row warning. No recorded corpus case carries a non-empty
/// `gate.ungated_below_bar`, so the whole warning loop in
/// `TrustRenderer+Scan.swift` was dead to the suite — a passing gate could stop
/// telling anyone that a below-bar row is not enforced, and nothing would fail.
struct TrustRendererGateTests {
  /// A `scan` result with a passing gate. `rows` is the whole status; `ungated`
  /// is the subset the gate reported below its bar, and only those may warn.
  private static func scanData(
    rows: [JSONValue]? = nil,
    ungated: [JSONValue],
  ) -> JSONValue {
    let statusRows = rows ?? ungated
    return .object(JSONObject([
      ("status", .object(JSONObject([
        ("summary", .object(JSONObject([("unproven", .number(Double(statusRows.count)))]))),
        ("rows", .array(statusRows)),
      ]))),
      ("gate", .object(JSONObject([
        ("required_bar", .string("VERIFIED_LOCAL")),
        ("blocked", .bool(false)),
        ("offending_rows", .array([])),
        ("ungated_below_bar", .array(ungated)),
      ]))),
    ]))
  }

  private static func row(
    _ identifier: String,
    status: String,
    localStatus: JSONValue = .null,
  ) -> JSONValue {
    .object(JSONObject([
      ("row_id", .string(identifier)),
      ("status", .string(status)),
      ("local_status", localStatus),
      ("required_for_release", .bool(false)),
      ("reasons", .array([])),
    ]))
  }

  @Test
  func `a passing gate still warns about every ungated row below the bar`() {
    let data = Self.scanData(ungated: [
      Self.row("probe.core.alpha", status: "UNPROVEN", localStatus: .string("STALE_LOCAL")),
      Self.row("probe.core.beta", status: "SUSPECT"),
    ])

    let lines = TrustRenderer.scanLines(data)

    #expect(lines
      .contains("\u{2713} gate passed \u{2014} 0 required behaviours meet VERIFIED_LOCAL."))
    #expect(lines.contains(
      "\u{26A0} probe.core.alpha is UNPROVEN/STALE_LOCAL but NOT gated \u{2014} "
        + "mark it `approval_policy.required_for_release: true` to enforce it.",
    ))
    #expect(lines.contains(
      "\u{26A0} probe.core.beta is SUSPECT but NOT gated \u{2014} "
        + "mark it `approval_policy.required_for_release: true` to enforce it.",
    ))
  }

  @Test(arguments: [
    (JSONValue.string("UNPROVEN"), JSONValue.null, "UNPROVEN"),
    (.string("UNPROVEN"), .string("VERIFIED_LOCAL"), "UNPROVEN/VERIFIED_LOCAL"),
    (.string("UNBOUND"), .string("STALE_LOCAL"), "UNBOUND"),
    (.null, .null, "below bar"),
  ])
  func `an ungated row's state pairs a local status only with UNPROVEN`(
    status: JSONValue,
    localStatus: JSONValue,
    expected: String,
  ) {
    let data = Self.scanData(ungated: [.object(JSONObject([
      ("row_id", .string("probe.core.alpha")),
      ("status", status),
      ("local_status", localStatus),
      ("required_for_release", .bool(false)),
      ("reasons", .array([])),
    ]))])

    let lines = TrustRenderer.scanLines(data)

    #expect(lines.contains { line in
      line.hasPrefix("\u{26A0} probe.core.alpha is \(expected) but NOT gated")
    }, "\(lines)")
  }

  @Test
  func `a gate with nothing below the bar warns about nothing`() {
    // Rows exist and are below the bar; the GATE is what decides, not the rows.
    let data = Self.scanData(
      rows: [
        Self.row("probe.core.alpha", status: "UNPROVEN", localStatus: .string("STALE_LOCAL")),
        Self.row("probe.core.beta", status: "SUSPECT"),
      ],
      ungated: [],
    )

    let lines = TrustRenderer.scanLines(data)

    #expect(lines.allSatisfy { line in
      !line.contains("NOT gated")
    })
  }
}
