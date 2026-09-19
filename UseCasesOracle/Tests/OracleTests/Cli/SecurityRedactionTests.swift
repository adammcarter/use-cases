import Foundation
import Testing

//: @use-case:security.redaction.secrets_never_reach_an_append_only_ledger#blackbox
/// The black-box oracle for security/redaction.yml.
///
/// Redaction happens at APPEND time, on the way into a ledger that is
/// append-only and usually committed. That is why it is worth a black-box test
/// rather than only a unit test of the matcher: what matters is not that the
/// regexes fire, but that a secret handed to `use-cases evidence record` cannot
/// be read back out of the stored event.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct SecurityRedactionTests {
  static let workspaceConfiguration = """
  schema_version: 1
  workspace_id: probe
  component_id: probe
  data_root: .
  use_cases_dir: use-cases
  evidence_dir: evidence
  demo_capsules_dir: demo-capsules
  showcase_runs_dir: showcase-runs
  default_workflow_mode: continuous

  """

  static let matrix = """
  schema_version: 1
  feature:
    id: probe.core
    name: Probe
    summary: Probe.
  use_cases:
    - id: probe.core.alpha
      title: Alpha
      lifecycle: active
      value_tier: core
      journey_role: golden
      usage_frequency: common
      actor: agent
      intent: Exist so evidence can be recorded against it.
      preconditions: [Nothing.]
      trigger: An agent records evidence.
      scenarios:
        - id: probe.core.alpha.golden_runs
          kind: steps
          steps: [Record it.]
          observable_outcomes: [It is stored redacted.]
      observable_outcomes: [Secrets never reach the ledger.]
      host_applicability:
        - host_surface: codex.cli
          supported: true
      verification_policy:
        mode: none
      approval_policy:
        mode: none

  """

  /// Record a summary and hand back what the ledger actually stored.
  static func storedSummary(_ summary: String) async throws -> String {
    let directory = try TemporaryDirectory("redaction")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: workspaceConfiguration)
    try directory.writeFile("use-cases/probe.yml", contents: matrix)
    let recorded = try await CliBinary.resolved().runJson(
      [
        "evidence", "record", "--repo", ".", "--use-case", "probe.core.alpha",
        "--summary", summary, "--idempotency-key", "redaction-\(UUID().uuidString)",
      ],
      cwd: directory.path,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
    #expect(recorded.isOk == true, "the record must be appended")
    return try #require(recorded.data.at("event.payload.summary")?.stringValue)
  }

  // golden_labelled_assignments. The LABEL survives so a reader can still see
  // what kind of thing was removed; the value does not. Its case is preserved
  // too, and the separator is normalised to `=` even when the input used a
  // colon — both measured through the CLI rather than read off the matcher.
  @Test
  func `labelled secret assignments are redacted, keeping the label and its case`()
    async throws
  {
    let stored = try await Self.storedSummary(
      "SECRET: hunter2 and token=abc123def and password: pw and api_key: k9",
    )

    #expect(stored.contains("SECRET=[redacted]"))
    #expect(stored.contains("token=[redacted]"))
    #expect(stored.contains("password=[redacted]"))
    #expect(stored.contains("api_key=[redacted]"))
    for secret in ["hunter2", "abc123def", "k9"] {
      #expect(!stored.contains(secret), Comment(rawValue: "\(secret) must not survive"))
    }
  }

  // golden_vendor_token_shapes. Each keeps enough prefix to identify what kind
  // of credential it was, which is what makes the record useful to act on.
  @Test
  func `vendor token shapes are redacted with their prefix left intact`() async throws {
    let stored = try await Self.storedSummary(
      """
      openai sk-ABCDEFGH12345678 github ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ012345 \
      aws AKIAIOSFODNN7EXAMPLE
      """,
    )

    #expect(stored.contains("sk-[redacted]"))
    #expect(stored.contains("ghp_[redacted]"))
    #expect(stored.contains("AKIA[redacted]"))
    let secrets = ["ABCDEFGH12345678", "ABCDEFGHIJKLMNOPQRSTUVWXYZ012345", "IOSFODNN7EXAMPLE"]
    for secret in secrets {
      #expect(!stored.contains(secret), Comment(rawValue: "\(secret) must not survive"))
    }
  }

  // bad_legitimate_prose_is_not_mangled. Over-redaction is its own failure:
  // records nobody can read are records nobody trusts.
  @Test
  func `text with no secret pattern is stored verbatim`() async throws {
    let prose = "The checkout flow worked and the receipt rendered correctly."
    #expect(try await Self.storedSummary(prose) == prose)
  }

  // edge_multiple_secrets_in_one_string. Every match, not just the first.
  @Test
  func `every distinct secret in one string is redacted, not only the first`()
    async throws
  {
    let stored = try await Self.storedSummary(
      "first token=aaaaaaaa then sk-BBBBBBBB12345678 then AKIAIOSFODNN7EXAMPLE end",
    )

    #expect(stored.contains("token=[redacted]"))
    #expect(stored.contains("sk-[redacted]"))
    #expect(stored.contains("AKIA[redacted]"))
    for secret in ["aaaaaaaa", "BBBBBBBB12345678", "IOSFODNN7EXAMPLE"] {
      #expect(!stored.contains(secret), Comment(rawValue: "\(secret) must not survive"))
    }
    // The surrounding prose is untouched, so the record still reads.
    #expect(stored.hasPrefix("first "))
    #expect(stored.hasSuffix(" end"))
  }
}

//: @use-case:end security.redaction.secrets_never_reach_an_append_only_ledger#blackbox
