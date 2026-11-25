/// A verify run with a start stamp and no completion marker (chapter 12 §6): started and waiting
/// for `verify --finish`, or stopped.
struct OpenVerifyRun: Equatable, Sendable {
  let stamp: StartStamp

  var identifier: RunIdentifier {
    stamp.identifier
  }
}
