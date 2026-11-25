@testable import UseCasesCore

extension StrictYAMLReader {
  /// Reads text and hands back what came of it, so a test can look at the refusal.
  func attempt(
    _ text: String,
    kind: AuthoredFileKind = .useCase,
    file: String = "use-cases/a.yml",
  ) -> Result<AuthoredValue, YAMLReadingError> {
    Result { () throws(YAMLReadingError) in
      try read(
        text,
        file: file,
        kind: kind,
      )
    }
  }
}

extension Result {
  var success: Success? {
    if case let .success(value) = self {
      value
    } else {
      nil
    }
  }

  var failure: Failure? {
    if case let .failure(error) = self {
      error
    } else {
      nil
    }
  }
}

extension AuthoredValue {
  /// An object whose members are written as pairs, in order.
  static func members(_ pairs: KeyValuePairs<String, AuthoredValue>) -> AuthoredValue {
    var members: [AuthoredMember] = []

    for (key, value) in pairs {
      members.append(
        AuthoredMember(
          key: key,
          value: value,
        ),
      )
    }

    return .object(members)
  }
}
