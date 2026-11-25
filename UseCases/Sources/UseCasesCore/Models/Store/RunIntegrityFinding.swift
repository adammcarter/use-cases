/// Damage to what a sealed run keeps beside its verdicts. It never changes a verdict and never
/// makes the run unreadable (chapter 12 §15 and §17), but the caller must not present the missing
/// evidence as intact.
enum RunIntegrityFinding: Equatable, Sendable {
  /// A report file no longer has the digest sealed in `completion.json`.
  case reportChanged(
    run: RunIdentifier,
    path: String,
  )

  /// A report file the marker lists is gone.
  case reportMissing(
    run: RunIdentifier,
    path: String,
  )

  /// A report file the marker does not list was written after the run was sealed.
  case reportAdded(
    run: RunIdentifier,
    path: String,
  )

  /// A blob a result's attachment names is missing or is not the bytes it names.
  case attachmentDamaged(
    run: RunIdentifier,
    useCase: UseCaseIdentifier,
    route: RouteIdentifier,
    name: String,
    damage: AttachmentDamage,
  )
}

extension RunIntegrityFinding: CustomStringConvertible {
  var description: String {
    switch self {
    case let .reportChanged(run, path):
      "run \(run): report \(path) changed after it was read"
    case let .reportMissing(run, path):
      "run \(run): report \(path) is missing"
    case let .reportAdded(run, path):
      "run \(run): report \(path) was added after the run was sealed"
    case let .attachmentDamaged(run, useCase, route, name, damage):
      "attachment \(AuthoredValue.quote(name)) of \(useCase) \(route) in run \(run) is damaged: " +
        damage.description
    }
  }
}
