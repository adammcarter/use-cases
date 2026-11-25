/// Why a name cannot be recorded as the one who signed off.
enum ApproverNameError: Error, Equatable, Sendable {
  /// Nothing is left of the name once the space around it is taken off.
  case blank

  /// The name is longer than ``ApproverName/longest`` characters.
  case tooLong(count: Int)

  /// The refusal as a person reads it.
  ///
  /// - Parameter flag: The option the name was given to, such as `--by`.
  func message(of flag: String) -> String {
    switch self {
    case .blank:
      "\(flag) names who signed off, so it cannot be blank"
    case let .tooLong(count):
      "\(flag) names who signed off in at most \(ApproverName.longest) characters; this has "
        + "\(count)"
    }
  }
}
