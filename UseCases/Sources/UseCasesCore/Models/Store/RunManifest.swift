/// What a run was and what happened (`run.json`, chapter 12 §11), for a manifest of a version this
/// core reads.
struct RunManifest: Equatable, Sendable {
  let identifier: RunIdentifier

  /// UTC RFC 3339, diagnostic only.
  let createdAt: String

  let kind: RunKind
  let sources: [RunSource]

  /// Run-level problems, such as a missing report. Never route verdicts.
  let errors: [String]

  let diagnostics: [RunDiagnostic]
  let unlinkedTests: [UnlinkedTest]
  let notes: [String]
}
