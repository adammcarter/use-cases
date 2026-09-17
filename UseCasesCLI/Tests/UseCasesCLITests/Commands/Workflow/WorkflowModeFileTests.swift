import Testing
@testable import UseCasesCLI

/// The line-anchored reads and rewrites of `default_workflow_mode` in
/// `use-cases.yml`, with JavaScript's multiline `^`, `\s` and `trimEnd`.
struct WorkflowModeFileTests {
  @Test(arguments: [
    ("default_workflow_mode: backfill\n", "backfill"),
    ("a: 1\ndefault_workflow_mode:custom", "custom"),
    ("a: 1\rdefault_workflow_mode: custom", "custom"),
    ("a: 1\u{2028}default_workflow_mode: custom", "custom"),
    ("default_workflow_mode:\n  audit_only\n", "audit_only"),
    ("default_workflow_mode:\u{FEFF}\u{00A0}showcase_only", "showcase_only"),
    ("default_workflow_mode: Backfill", "continuous"),
    ("default_workflow_mode: back-fill", "back"),
    ("default_workflow_mode: \"x\"\ndefault_workflow_mode: custom", "custom"),
    (" default_workflow_mode: custom", "continuous"),
    ("", "continuous"),
  ])
  func `reads the first line-anchored mode`(
    source: String,
    expected: String,
  ) {
    #expect(WorkflowModeFile.mode(in: source) == expected)
  }

  @Test(arguments: [
    (
      "a: 1\ndefault_workflow_mode: continuous\nb: 2\n",
      "custom",
      "a: 1\ndefault_workflow_mode: custom\nb: 2\n"
    ),
    (
      "default_workflow_mode:\n  audit_only\nb: 2\n",
      "custom",
      "default_workflow_mode: custom\nb: 2\n"
    ),
    ("default_workflow_mode: \"x\"\n", "custom", "default_workflow_mode: \"x\"\n"),
    ("a: 1\n\n \t", "backfill", "a: 1\ndefault_workflow_mode: backfill\n"),
    ("", "backfill", "\ndefault_workflow_mode: backfill\n"),
    (
      "x default_workflow_mode: a\n",
      "custom",
      "x default_workflow_mode: a\ndefault_workflow_mode: custom\n"
    ),
  ])
  func `rewrites or appends the mode`(
    source: String,
    mode: String,
    expected: String,
  ) {
    #expect(WorkflowModeFile.replacingMode(in: source, with: mode) == expected)
  }

  @Test(arguments: [
    ("continuous", "continuous" as String?),
    ("showcase-only", "showcase_only"),
    ("audit-only", "audit_only"),
    ("back-fill", nil),
    ("custom", "custom"),
    ("migration", nil),
    ("Continuous", nil),
    ("", nil),
  ])
  func `canonicalizes a requested mode`(
    value: String,
    expected: String?,
  ) {
    #expect(WorkflowModeFile.canonicalMode(value) == expected)
  }

  @Test
  func `refuses an absent mode`() {
    #expect(WorkflowModeFile.canonicalMode(nil) == nil)
  }
}
