/// A storage error (chapter 12 §24): something in the store that cannot be trusted or read. It is
/// not the route status `error`, which records a validation failure for a known fingerprint.
struct StoreProblem: Error, Hashable, Comparable, Sendable, CustomStringConvertible {
  /// What is wrong.
  enum Reason: Hashable, Sendable {
    /// The file is there but breaks its schema, is not JSON, or disagrees with the sealed run's
    /// marker.
    case corrupt(String)

    /// The file is well formed but written by a version of the store this core cannot use for the
    /// purpose (an allocation file of a newer version, say).
    case unsupported(String)

    /// An entry of `runs/` that is not a run id and not a recognized temporary folder.
    case notARunFolder

    /// A place that has to be a folder and is not.
    case notAFolder

    /// The system would not let the store be read.
    case unreadable(String)
  }

  /// The place, relative to the workspace root, such as `.use-cases/runs/<id>/results.jsonl`.
  let location: String

  let reason: Reason

  /// `<location> is corrupt: <why>`, `<location> is not a run folder`, and so on.
  var description: String {
    switch reason {
    case let .corrupt(detail):
      "\(location) is corrupt: \(detail)"
    case let .unsupported(detail):
      "\(location) is unsupported: \(detail)"
    case .notARunFolder:
      "\(location) is not a run folder"
    case .notAFolder:
      "\(location) is not a folder"
    case let .unreadable(detail):
      "\(location) cannot be read: \(detail)"
    }
  }

  static func < (
    lhs: StoreProblem,
    rhs: StoreProblem,
  ) -> Bool {
    if lhs.location != rhs.location {
      return lhs.location.precedesExactly(rhs.location)
    }

    return lhs.description.precedesExactly(rhs.description)
  }

  static func unsupported(
    _ location: String,
    _ detail: String,
  ) -> StoreProblem {
    StoreProblem(
      location: location,
      reason: .unsupported(detail),
    )
  }

  static func corrupt(
    _ location: String,
    _ detail: String,
  ) -> StoreProblem {
    StoreProblem(
      location: location,
      reason: .corrupt(detail),
    )
  }
}
