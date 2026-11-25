import Foundation
import UseCasesCore

/// The real writer, which says where it was asked to write by adding a line to a log file, and
/// does something of the test's after it has written. Writing to a log file keeps the spy a value
/// the command line can hold without sharing state.
struct SpyPlanWriting: PlanWriting {
  let writer = AtomicPlanWriter()
  let log: URL
  let afterApplying: @Sendable () -> Void

  /// - Parameters:
  ///   - log: The file that gets one line, the folder written to, for each plan applied.
  ///   - afterApplying: Called once each time plans have been written.
  init(
    log: URL,
    afterApplying: @escaping @Sendable () -> Void = {},
  ) {
    self.log = log
    self.afterApplying = afterApplying
  }

  /// The folders written to, in order.
  var applied: [String] {
    ((try? String(contentsOf: log, encoding: .utf8)) ?? "")
      .split(separator: "\n")
      .map(String.init)
  }

  func apply(
    _ writes: [FolderWrite],
    lockingIn workspace: URL,
  ) throws(PlanWritingError) {
    try writer.apply(
      writes,
      lockingIn: workspace,
    )

    let lines = applied + writes.map(\.folder.path)
    try? Data((lines.joined(separator: "\n") + "\n").utf8).write(to: log)
    afterApplying()
  }
}
