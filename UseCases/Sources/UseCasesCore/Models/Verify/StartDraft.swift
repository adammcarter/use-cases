/// Everything `start.json` holds that is known before the run has an id and a time: what the
/// start point noted (chapter 13 §5) and the sources the run plans to read.
struct StartDraft: Equatable, Sendable {
  let openedBy: RunOpener

  /// The validations this run reads, in the order of the bridge settings.
  let selected: [IdentifierSegment]

  /// The SHA-256 of those validations exactly as the bridge settings wrote them.
  let validationsDigest: String

  /// Every route's fingerprint.
  let routes: [StartedRoute]

  /// The SHA-256 of every linked and resource file, sorted by path.
  let files: [FileDigest]

  /// The initial manifest's `sources`: one planned entry for each selected validation.
  let sources: [RunSource]
}
