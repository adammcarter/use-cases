import Foundation
import UseCasesCore

/// The real writer, after something else has changed the files: what another process does between
/// a command planning its change and writing it, made to happen at that moment.
struct ChangingPlanWriting: PlanWriting {
  let writer = AtomicPlanWriter()
  let change: @Sendable () -> Void

  /// - Parameter change: Done once each time plans are about to be written, before the writer
  ///   looks at the files.
  init(change: @escaping @Sendable () -> Void) {
    self.change = change
  }

  func apply(
    _ writes: [FolderWrite],
    lockingIn workspace: URL,
  ) throws(PlanWritingError) {
    change()

    try writer.apply(
      writes,
      lockingIn: workspace,
    )
  }
}
