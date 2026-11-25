import Foundation

/// What `use-cases record` was asked to store (chapter 13 §12): the words of the command line,
/// not yet checked against the workspace.
public struct RecordRequest: Equatable, Sendable {
  /// A use case id, or the start of one.
  public let useCase: String

  /// A route id of that use case, or the start of one.
  public let route: String

  /// `pass`, `fail`, `incomplete` or `error`.
  public let status: String

  /// The note that goes with the verdict, when one was given.
  public let message: String?

  /// Files to keep with the verdict as evidence, in the order given. Each is read when the
  /// request is planned.
  public let attachments: [URL]

  /// Makes the request.
  public init(
    useCase: String,
    route: String,
    status: String,
    message: String?,
    attachments: [URL],
  ) {
    self.useCase = useCase
    self.route = route
    self.status = status
    self.message = message
    self.attachments = attachments
  }
}
