import Foundation
import UseCasesCore

/// What `init` is to set up: the flags of the command line, then each answer that changes them.
struct InitSetup {
  var form: InitForm
  var prefix: String?

  /// The hooks to add; `nil` when nothing has said, which a person at a terminal is asked.
  var hooks: [HookName]?

  func request(in folder: URL) -> InitRequest {
    InitRequest(
      folder: folder,
      form: form,
      prefix: prefix,
    )
  }
}
