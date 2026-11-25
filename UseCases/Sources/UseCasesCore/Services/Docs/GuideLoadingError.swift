/// Why the guides that ship with the build cannot be read.
public enum GuideLoadingError: Error, Equatable, Sendable {
  /// The build holds no copy of the guide.
  case missing(String)

  /// The copy is not UTF-8 text.
  case unreadable(String)

  /// The copy is not a guide: it has no title, or no paragraph under it saying what it covers.
  case invalid(String)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .missing(name):
      "this build has no copy of the guide '\(name)'"
    case let .unreadable(name):
      "the guide '\(name)' is not text"
    case let .invalid(name):
      "the guide '\(name)' has no title, or no first paragraph saying what it covers"
    }
  }
}
