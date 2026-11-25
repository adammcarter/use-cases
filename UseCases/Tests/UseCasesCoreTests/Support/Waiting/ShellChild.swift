import Foundation
import UseCasesTestSupport

/// A child shell a test started, kept while it runs.
struct ShellChild {
  let process: Process
  let holders: PipeHolders

  /// Returns once the shell and everything it started that kept its output have gone.
  func allGone() async {
    await holders.allGone()
  }
}
