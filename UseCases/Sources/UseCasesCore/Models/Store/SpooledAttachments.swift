/// The attachments of a request as they were when it was checked, with the folder that holds the
/// copies. The copies stay for as long as anything holds this.
struct SpooledAttachments: Equatable, Sendable {
  /// Nothing was given as evidence.
  static let none = SpooledAttachments(
    folder: nil,
    files: [],
  )

  /// The folder of the copies; `nil` when there are none.
  let folder: AttachmentSpoolFolder?

  /// In the order they were given.
  let files: [SpooledAttachment]
}
