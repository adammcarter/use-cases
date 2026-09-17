/// An entry in the workspace config's `verifiers` map: an explicit script
/// verifier, or a reference to a preset.
///
/// Kept structurally loose, exactly as the TypeScript keeps it: the schema
/// (`common.schema.json#/$defs/verifier`) is the source of truth for the shape,
/// so the raw object is carried through untouched and an additive change to the
/// schema needs no lockstep edit here.
public struct WorkspaceVerifierEntry: Sendable, Equatable {
  /// The entry as the config carried it, member for member.
  public let value: JSONObject

  public init(value: JSONObject) {
    self.value = value
  }

  /// `"script"` for an explicit verifier; absent for a preset reference.
  public var kind: String? {
    value["kind"]?.stringValue
  }

  /// The preset this entry refers to; absent for an explicit verifier.
  public var preset: String? {
    value["preset"]?.stringValue
  }

  /// The kind of evidence running this verifier mints.
  public var evidenceKind: String? {
    value["evidence_kind"]?.stringValue
  }

  /// The argv an explicit verifier runs, or nil when any member is not a string.
  public var command: [String]? {
    stringArray(forKey: "command")
  }

  /// The inputs whose contents feed the verifier's context hash.
  public var inputs: [String]? {
    stringArray(forKey: "inputs")
  }

  /// How long the verifier may run before it is abandoned.
  public var timeoutSeconds: Double? {
    value["timeout_seconds"]?.numberValue
  }

  private func stringArray(forKey key: String) -> [String]? {
    guard let members = value[key]?.arrayValue else {
      return nil
    }
    var texts: [String] = []
    for member in members {
      guard let text = member.stringValue else {
        return nil
      }
      texts.append(text)
    }
    return texts
  }
}

/// The workspace config's `verifiers` section, normalized for the verifier
/// resolver: the `default` id split out from the entry map.
public struct ResolvedWorkspaceVerifiers: Sendable, Equatable {
  /// The verifier id a row with none of its own falls back to.
  public let defaultVerifierIdentifier: String?

  /// Every declared verifier, by id.
  public let verifiers: [String: WorkspaceVerifierEntry]

  public init(
    defaultVerifierIdentifier: String? = nil,
    verifiers: [String: WorkspaceVerifierEntry] = [:],
  ) {
    self.defaultVerifierIdentifier = defaultVerifierIdentifier
    self.verifiers = verifiers
  }

  /// Split a raw `verifiers` config into the default id and the entry map.
  ///
  /// The schema guarantees entries are objects and `default` is a string; both
  /// are re-checked here because the config is hand-edited.
  static func normalize(_ raw: JSONValue?) -> ResolvedWorkspaceVerifiers {
    guard let object = raw?.objectValue else {
      return ResolvedWorkspaceVerifiers()
    }
    var verifiers: [String: WorkspaceVerifierEntry] = [:]
    for pair in object.pairs where pair.key != "default" {
      guard let entry = pair.value.objectValue else {
        continue
      }
      verifiers[pair.key] = WorkspaceVerifierEntry(value: entry)
    }
    return ResolvedWorkspaceVerifiers(
      defaultVerifierIdentifier: object["default"]?.stringValue,
      verifiers: verifiers,
    )
  }
}

/// The release-gate authority a workspace requires before a
/// `required_for_release` row may pass in RELEASE mode. Off by default.
public struct WorkspaceReleaseGate: Sendable, Equatable {
  /// The authority shape a proof must carry. CI-neutral: only the shape is
  /// inspected, never which provider produced it.
  public enum RequiredAuthority: String, Sendable, Equatable {
    case continuousIntegration = "ci"
  }

  public let requiredAuthority: RequiredAuthority?
  public let requiresProtectedReference: Bool?

  public init(
    requiredAuthority: RequiredAuthority? = nil,
    requiresProtectedReference: Bool? = nil,
  ) {
    self.requiredAuthority = requiredAuthority
    self.requiresProtectedReference = requiresProtectedReference
  }

  /// Read the optional `release_gate` config, or nil when nothing meaningful is
  /// set — an empty or all-falsy object means "no requirement", which is
  /// today's behaviour unchanged.
  static func normalize(_ raw: JSONValue?) -> WorkspaceReleaseGate? {
    guard let object = raw?.objectValue else {
      return nil
    }
    let authority: RequiredAuthority? = object["required_authority"] == .string("ci")
      ? .continuousIntegration
      : nil
    let protectedReference: Bool? = object["require_protected_ref"] == .bool(true) ? true : nil

    guard authority != nil || protectedReference != nil else {
      return nil
    }
    return WorkspaceReleaseGate(
      requiredAuthority: authority,
      requiresProtectedReference: protectedReference,
    )
  }
}

/// The workspace-pinned trust anchor for verifying signed showcase approval
/// tokens. When present it is authoritative: caller flags may narrow it, never
/// introduce a new verifying root.
public struct WorkspaceApprovalTrust: Sendable, Equatable {
  /// A repository-relative path to a committed keyring.
  public let keyringPath: String?

  /// An inline keyring, carried raw until the keyring row gives it a type.
  public let keyring: JSONValue?

  /// Inline trusted public keys, carried raw until the keyring row gives them
  /// a type.
  public let publicKeys: [JSONValue]?

  public init(
    keyringPath: String? = nil,
    keyring: JSONValue? = nil,
    publicKeys: [JSONValue]? = nil,
  ) {
    self.keyringPath = keyringPath
    self.keyring = keyring
    self.publicKeys = publicKeys
  }

  /// Read the optional `approval_trust` config, or nil when it pins nothing.
  static func normalize(_ raw: JSONValue?) -> WorkspaceApprovalTrust? {
    guard let object = raw?.objectValue else {
      return nil
    }
    let keyringPath = object["keyring_path"]?.stringValue
    let keyring = object["keyring"]?.isRecord == true ? object["keyring"] : nil
    let publicKeys = object["public_keys"]?.arrayValue

    guard WorkspaceContextResolver.isTruthy(keyringPath)
      || keyring != nil
      || publicKeys != nil
    else {
      return nil
    }
    return WorkspaceApprovalTrust(
      keyringPath: keyringPath,
      keyring: keyring,
      publicKeys: publicKeys,
    )
  }
}
