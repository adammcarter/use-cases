/// Why a use case could not be saved or removed (chapter 16 §14). Every refusal is found before
/// the first byte is written.
public enum UseCaseEditingError: Error, Equatable, Sendable {
  /// The input could not be read.
  case input(message: String)

  /// The input is not one mapping that names the use case by its full id.
  case notAUseCase(name: String)

  /// The id is not an id.
  case invalidIdentifier(message: String)

  /// The id has no group in it at all.
  case noGroup(identifier: String)

  /// The id sits straight under a scope's namespace.
  case needsGroup(
    identifier: String,
    namespace: String,
  )

  /// The id is not under the namespace of any scope.
  case outsideNamespaces(
    identifier: String,
    namespace: String,
  )

  /// The workspace has no use case with this id.
  case unknown(identifier: String)

  /// The use case breaks the rules every use case file is held to. One problem to a line.
  case invalidUseCase(
    name: String,
    problems: [String],
  )

  /// The input brings a sign-off that is not the one the use case has.
  case approvalNotBySave(identifier: String)

  /// The file the use case is in cannot be edited by its lines.
  case unsupportedLayout(
    file: String,
    reason: String,
  )

  /// The file the use case is in could not be read.
  case unreadable(
    file: String,
    reason: String,
  )

  /// The file as the edit writes it would not read as the use cases it should hold.
  case wouldNotReadBack(file: String)

  /// How a script is told about the refusal (chapter 16 §5).
  public enum Kind: Equatable, Sendable {
    /// The request itself is wrong: an input, an id, or a use case that is not there.
    case usage

    /// The workspace would be INVALID after the change.
    case invalid

    /// A valid request that cannot proceed.
    case refused
  }

  /// How a script is told about the refusal.
  public var kind: Kind {
    switch self {
    case .input, .notAUseCase, .invalidIdentifier, .noGroup, .needsGroup, .outsideNamespaces,
         .unknown, .approvalNotBySave:
      .usage
    case .invalidUseCase:
      .invalid
    case .unsupportedLayout, .unreadable, .wouldNotReadBack, .schemasUnavailable:
      .refused
    }
  }

  /// The schemas that ship inside this build could not be loaded, so nothing could be checked.
  case schemasUnavailable(message: String)

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .input(message), let .invalidIdentifier(message), let .schemasUnavailable(message):
      message
    case let .notAUseCase(name):
      "\(name) is not one mapping with its full id: a use case is a YAML or JSON mapping whose "
        + "`id` is its full id, such as shop.login.lockout"
    case let .noGroup(identifier):
      "'\(identifier)' has no group: a full id is its namespace, a group and its own id, "
        + "such as shop.login.lockout"
    case let .needsGroup(identifier, namespace):
      "'\(identifier)' sits straight under '\(namespace)': use cases need a group, "
        + "as in \(namespace).<group>.\(identifier.lastSegment)"
    case let .outsideNamespaces(identifier, namespace):
      "'\(identifier)' is not under this workspace's namespace '\(namespace)'"
    case let .unknown(identifier):
      "no use case '\(identifier)' in this workspace; it takes a use case's full id"
    case let .invalidUseCase(name, problems):
      problems.map { problem in
        "\(name): \(problem)"
      }.joined(separator: "\n")
    case let .approvalNotBySave(identifier):
      "'\(identifier)' brings a sign-off it does not have: a sign-off is recorded by approve, "
        + "never by save"
    case let .unsupportedLayout(file, reason):
      "\(file) cannot be edited by its lines: \(reason)"
    case let .unreadable(file, reason):
      "\(file) cannot be read: \(reason)"
    case let .wouldNotReadBack(file):
      "\(file) would not read back as the use cases it should hold, so nothing was written"
    }
  }
}

private extension String {
  var lastSegment: String {
    String(split(separator: ".").last ?? "")
  }
}
