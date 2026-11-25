import Foundation

/// What `use-cases init` was asked to set up (chapter 17 §1): the words of the command line,
/// not yet checked against the folder.
public struct InitRequest: Equatable, Sendable {
  /// The folder to set up: where the command runs, or the one `--workspace` names.
  public let folder: URL

  public let form: InitForm

  /// The root prefix `--prefix` asked for, as written.
  public let prefix: String?

  /// Makes the request.
  public init(
    folder: URL,
    form: InitForm,
    prefix: String?,
  ) {
    self.folder = folder
    self.form = form
    self.prefix = prefix
  }
}
