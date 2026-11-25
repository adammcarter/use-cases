import Foundation
import UseCasesCore

/// What `save` and `remove` are done with: planning the change to the use case's lines.
struct EditTools {
  let saver: any UseCaseSaving
  let remover: any UseCaseRemoving

  /// - Parameters:
  ///   - workingDirectory: Where a relative path given to `--file` is read from.
  ///   - saver: Plans a save.
  ///   - remover: Plans a remove.
  init(
    workingDirectory: URL,
    saver: (any UseCaseSaving)? = nil,
    remover: any UseCaseRemoving = UseCaseRemover(),
  ) {
    self.saver = saver ?? UseCaseSaver(workingDirectory: workingDirectory)
    self.remover = remover
  }
}
