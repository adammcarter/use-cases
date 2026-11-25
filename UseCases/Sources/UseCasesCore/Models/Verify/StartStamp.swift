/// The code as it was when a verify run began, and which request opened the run (`start.json`,
/// chapter 12 §11). Written once, before any test runs, and never changed.
struct StartStamp: Equatable, Sendable {
  let identifier: RunIdentifier

  /// UTC RFC 3339, diagnostic only.
  let startedAt: String

  let openedBy: RunOpener
  let selected: [IdentifierSegment]
  let validationsDigest: String
  let routes: [StartedRoute]
  let files: [FileDigest]
}
