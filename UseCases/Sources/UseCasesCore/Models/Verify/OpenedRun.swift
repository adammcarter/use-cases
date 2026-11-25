/// A verify run the start point has just opened and holds (chapter 13 §5), with the validations
/// it reads.
struct OpenedRun: Equatable, Sendable {
  /// The run, published and not sealed.
  let run: OpenRun

  /// The run's lock, held since before the run was published. Release it when the request is
  /// done with the run.
  let lock: HeldRunLock

  /// The validations the run reads, in the order of the bridge settings.
  let selected: [BridgeValidation]
}
