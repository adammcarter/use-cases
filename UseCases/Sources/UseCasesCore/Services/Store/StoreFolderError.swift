/// Why the file system refused to move or delete something of the store for `prune`.
struct StoreFolderError: Error, Equatable, Sendable, CustomStringConvertible {
  /// What the system said, as a person reads it, with no full stop at the end.
  let reason: String

  init(reason: String) {
    var text = reason

    while text.hasSuffix(".") {
      text.removeLast()
    }

    self.reason = text
  }

  var description: String {
    reason
  }
}
