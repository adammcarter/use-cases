/// The `protected_ref` tri-state: absent from the record, `null` (unknown),
/// or a boolean the provider attested.
public enum ProtectedReference: Equatable, Sendable {
  case omitted
  case unknown
  case known(Bool)
}

public enum CiAuthorityType: String, Equatable, Sendable {
  case continuousIntegration = "ci"
  case local
}

public enum CiProvider: String, Equatable, Sendable {
  case gitHubActions = "github-actions"
  case gitLabCI = "gitlab-ci"
  case circleCI = "circleci"
  case generic
}

/// The CI-neutral provenance authority (ciAuthority.ts; mirrors
/// schemas/v1/authority.schema.json). When `prove` embeds it, it is built into
/// the event before signing, so the signature covers it.
public struct CiAuthority: Equatable, Sendable {
  public let type: CiAuthorityType
  public let provider: CiProvider
  public let repository: String?
  public let reference: String?
  public let commit: String?
  public let runIdentifier: String?
  public let actor: String?
  public let protectedReference: ProtectedReference
  public let event: String?

  /// Only the fields that are present, in the TypeScript's order.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("type", .string(type.rawValue)),
      ("provider", .string(provider.rawValue)),
    ])
    object["repository"] = repository.map(JSONValue.string)
    object["ref"] = reference.map(JSONValue.string)
    object["commit"] = commit.map(JSONValue.string)
    object["run_id"] = runIdentifier.map(JSONValue.string)
    object["actor"] = actor.map(JSONValue.string)
    switch protectedReference {
    case .omitted:
      break
    case .unknown:
      object["protected_ref"] = .null
    case let .known(flag):
      object["protected_ref"] = .bool(flag)
    }
    object["event"] = event.map(JSONValue.string)
    return .object(object)
  }

  /// Read the authority off a CI environment map. The environment is passed in,
  /// never read from the process, so a caller owns the impurity.
  ///
  /// `protectedReferenceOverride`, when given, replaces the provider's signal;
  /// `.omitted` reproduces the TypeScript's `{ protectedRef: undefined }`.
  public static func detect(
    environment: [String: String],
    protectedReferenceOverride: ProtectedReference? = nil,
  ) -> CiAuthority {
    let signals = EnvironmentSignals(environment: environment)
    if isSet(environment["GITHUB_ACTIONS"]) {
      return signals.authority(
        provider: .gitHubActions,
        names: ["GITHUB_REPOSITORY", "GITHUB_REF", "GITHUB_SHA", "GITHUB_RUN_ID", "GITHUB_ACTOR"],
        protectedReference: protectedReferenceOverride ?? .unknown,
        event: signals.value("GITHUB_EVENT_NAME"),
      )
    }
    if isSet(environment["GITLAB_CI"]) {
      return signals.authority(
        provider: .gitLabCI,
        names: [
          "CI_PROJECT_PATH", "CI_COMMIT_REF_NAME", "CI_COMMIT_SHA", "CI_PIPELINE_ID",
          "GITLAB_USER_LOGIN",
        ],
        protectedReference: protectedReferenceOverride
          ?? protectedSignal(environment["CI_COMMIT_REF_PROTECTED"]),
        event: signals.value("CI_PIPELINE_SOURCE"),
      )
    }
    if isSet(environment["CIRCLECI"]) {
      return signals.circleAuthority(protectedReference: protectedReferenceOverride ?? .unknown)
    }
    return CiAuthority(
      type: .local,
      provider: .generic,
      repository: nil,
      reference: nil,
      commit: nil,
      runIdentifier: nil,
      actor: nil,
      protectedReference: protectedReferenceOverride ?? .omitted,
      event: nil,
    )
  }

  private static func isSet(_ value: String?) -> Bool {
    guard let value else {
      return false
    }
    return !value.isEmpty
  }

  /// Exactly `"true"` or `"false"`; anything else is unknown.
  private static func protectedSignal(_ value: String?) -> ProtectedReference {
    switch value {
    case "true": .known(true)
    case "false": .known(false)
    default: .unknown
    }
  }
}

/// The provider variables a detection reads, trimmed as JavaScript trims.
private struct EnvironmentSignals {
  let environment: [String: String]

  /// A non-empty trimmed value, or nil so the field is omitted.
  func value(_ name: String) -> String? {
    guard let raw = environment[name] else {
      return nil
    }
    let trimmed = JavaScriptString.trim(raw)
    return trimmed.isEmpty ? nil : trimmed
  }

  /// `names` are, in order: repository, ref, commit, run id, actor.
  func authority(
    provider: CiProvider,
    names: [String],
    protectedReference: ProtectedReference,
    event: String?,
  ) -> CiAuthority {
    let values = names.map(value)
    return CiAuthority(
      type: .continuousIntegration,
      provider: provider,
      repository: values[0],
      reference: values[1],
      commit: values[2],
      runIdentifier: values[3],
      actor: values[4],
      protectedReference: protectedReference,
      event: event,
    )
  }

  /// CircleCI joins owner and repository as `owner/repo` when it has both.
  func circleAuthority(protectedReference: ProtectedReference) -> CiAuthority {
    let owner = value("CIRCLE_PROJECT_USERNAME")
    let repository = value("CIRCLE_PROJECT_REPONAME")
    let joined = if let owner, let repository {
      "\(owner)/\(repository)"
    } else {
      repository ?? owner
    }
    return CiAuthority(
      type: .continuousIntegration,
      provider: .circleCI,
      repository: joined,
      reference: value("CIRCLE_BRANCH"),
      commit: value("CIRCLE_SHA1"),
      runIdentifier: value("CIRCLE_BUILD_NUM"),
      actor: value("CIRCLE_USERNAME"),
      protectedReference: protectedReference,
      event: nil,
    )
  }
}
