/// Where a resolved verifier's entry was found.
public enum VerifierSource: String, Equatable, Sendable {
  case policy
  case workspaceConfiguration = "workspace_config"
  case workspaceDefault = "workspace_default"
}

/// A verifier the row's policy demands, resolved to a concrete script.
public struct ResolvedVerifier: Equatable, Sendable {
  public let verifierIdentifier: String
  public let source: VerifierSource
  public let evidenceKind: String
  public let command: [String]
  public let inputs: [String]
  public let timeoutSeconds: Double?
  /// The preset this verifier expanded from; nil for an explicit script. It is
  /// the only mechanical way to tell a named test runner from arbitrary argv.
  public let preset: VerifierPresetIdentifier?

  public init(
    verifierIdentifier: String,
    source: VerifierSource,
    evidenceKind: String,
    command: [String],
    inputs: [String],
    timeoutSeconds: Double?,
    preset: VerifierPresetIdentifier?,
  ) {
    self.verifierIdentifier = verifierIdentifier
    self.source = source
    self.evidenceKind = evidenceKind
    self.command = command
    self.inputs = inputs
    self.timeoutSeconds = timeoutSeconds
    self.preset = preset
  }

  /// The TypeScript object: `preset` is written before `timeout_seconds`,
  /// because the timeout is assigned after the literal is built.
  var jsonValue: JSONValue {
    var object = JSONObject([
      ("verifier_id", .string(verifierIdentifier)),
      ("status", .string("resolved")),
      ("source", .string(source.rawValue)),
      ("kind", .string("script")),
      ("evidence_kind", .string(evidenceKind)),
      ("command", .array(command.map(JSONValue.string))),
      ("inputs", .array(inputs.map(JSONValue.string))),
    ])
    object["preset"] = preset.map { preset in
      .string(preset.rawValue)
    }
    object["timeout_seconds"] = timeoutSeconds.map(JSONValue.number)
    return .object(object)
  }
}

/// A verifier that could not be resolved, with the actionable reason.
public struct BlockedVerifier: Equatable, Sendable {
  public let verifierIdentifier: String
  public let reason: String

  public init(
    verifierIdentifier: String,
    reason: String,
  ) {
    self.verifierIdentifier = verifierIdentifier
    self.reason = reason
  }

  var jsonValue: JSONValue {
    .object(JSONObject([
      ("verifier_id", .string(verifierIdentifier)),
      ("status", .string("blocked")),
      ("reason", .string(reason)),
    ]))
  }
}

public enum VerifierResolution: Equatable, Sendable {
  case resolved(ResolvedVerifier)
  case blocked(BlockedVerifier)

  public var verifierIdentifier: String {
    switch self {
    case let .resolved(verifier): verifier.verifierIdentifier
    case let .blocked(verifier): verifier.verifierIdentifier
    }
  }

  var jsonValue: JSONValue {
    switch self {
    case let .resolved(verifier): verifier.jsonValue
    case let .blocked(verifier): verifier.jsonValue
    }
  }
}

/// Resolve the concrete verifier(s) a row's verification_policy demands
/// (verifierResolver.ts). Each required id resolves, in order, from the row's
/// own `verifiers`, the workspace config's `verifiers`, and — for the default
/// convention id only — the entry the workspace's `default` names; otherwise it
/// is BLOCKED, returned rather than thrown.
public enum VerifierResolver {
  /// The id rows use for "the workspace default verifier". It has no built-in
  /// command.
  public static let defaultConventionVerifierIdentifier = "acceptance"

  /// Every required verifier id, deduplicated, resolved and sorted by id in
  /// UTF-16 code-unit order.
  public static func resolveRowVerifiers(
    slug: String,
    variant: String? = nil,
    verificationPolicy: JSONValue?,
    workspace: ResolvedWorkspaceVerifiers = ResolvedWorkspaceVerifiers(),
  ) -> [VerifierResolution] {
    let rowVerifiers = verificationPolicy?["verifiers"]?.objectValue ?? JSONObject()
    let context = ResolutionContext(
      slug: slug,
      variant: variant,
      rowVerifiers: rowVerifiers,
      workspace: workspace,
    )
    let resolutions = requiredVerifierIdentifiers(verificationPolicy).map(context.resolve)
    return sortedByIdentifier(resolutions)
  }

  /// Stable, by `verifier_id` in code-unit order.
  static func sortedByIdentifier(_ resolutions: [VerifierResolution]) -> [VerifierResolution] {
    resolutions.enumerated()
      .sorted { left, right in
        let leftIdentifier = left.element.verifierIdentifier
        let rightIdentifier = right.element.verifierIdentifier
        if JavaScriptString.precedes(leftIdentifier, rightIdentifier) {
          return true
        }
        if JavaScriptString.precedes(rightIdentifier, leftIdentifier) {
          return false
        }
        return left.offset < right.offset
      }
      .map(\.element)
  }

  private static func requiredVerifierIdentifiers(_ policy: JSONValue?) -> [String] {
    guard let policy = policy?.objectValue,
          policy["mode"] == .string("requirements"),
          let requirements = policy["requirements"]?.arrayValue
    else {
      return []
    }
    var seen = OrderedStringSet()
    for requirement in requirements {
      guard let identifiers = requirement["required_verifiers"]?.arrayValue else {
        continue
      }
      for identifier in identifiers.compactMap(\.stringValue) {
        seen.insert(identifier)
      }
    }
    return seen.members
  }
}

private struct ResolutionContext {
  let slug: String
  let variant: String?
  let rowVerifiers: JSONObject
  let workspace: ResolvedWorkspaceVerifiers

  func resolve(_ identifier: String) -> VerifierResolution {
    if let entry = rowVerifiers[identifier]?.objectValue {
      return resolveEntry(identifier, entry, source: .policy)
    }
    if let entry = workspaceEntry(identifier) {
      return resolveEntry(identifier, entry, source: .workspaceConfiguration)
    }
    if JavaScriptString.identical(identifier, VerifierResolver.defaultConventionVerifierIdentifier),
       let defaultIdentifier = workspace.defaultVerifierIdentifier
    {
      if let target = workspaceEntry(defaultIdentifier) {
        return resolveEntry(identifier, target, source: .workspaceDefault)
      }
      return .blocked(BlockedVerifier(
        verifierIdentifier: identifier,
        reason: "workspace verifiers.default '\(defaultIdentifier)' "
          + "does not name a declared verifier",
      ))
    }
    return .blocked(BlockedVerifier(
      verifierIdentifier: identifier,
      reason: "no verifier '\(identifier)' configured; declare it in the row's "
        + "verification_policy.verifiers or the workspace verifiers map, or set verifiers.default",
    ))
  }

  /// The workspace entry whose id has exactly these code units. Not a
  /// dictionary subscript: Swift's `String` keys match canonically equivalent
  /// ids, which the TypeScript's property lookup never does.
  private func workspaceEntry(_ identifier: String) -> JSONObject? {
    workspace.verifiers.first { pair in
      JavaScriptString.identical(pair.key, identifier)
    }?.value.value
  }

  private func resolveEntry(
    _ identifier: String,
    _ entry: JSONObject,
    source: VerifierSource,
  ) -> VerifierResolution {
    let evidenceKind = entry["evidence_kind"]?.stringValue ?? "test_result"
    let timeoutSeconds = entry["timeout_seconds"]?.numberValue
    guard let presetIdentifier = entry["preset"]?.stringValue else {
      return .resolved(ResolvedVerifier(
        verifierIdentifier: identifier,
        source: source,
        evidenceKind: evidenceKind,
        command: substituted(entry["command"]),
        inputs: substituted(entry["inputs"]),
        timeoutSeconds: timeoutSeconds,
        preset: nil,
      ))
    }
    switch VerifierPresets
      .expand(presetIdentifier: presetIdentifier, slug: slug, variant: variant)
    {
    case let .blocked(reason):
      return .blocked(BlockedVerifier(verifierIdentifier: identifier, reason: reason))
    case let .resolved(preset, expansion):
      let inputs = entry["inputs"]?.arrayValue == nil
        ? expansion.inputs
        : substituted(entry["inputs"])
      return .resolved(ResolvedVerifier(
        verifierIdentifier: identifier,
        source: source,
        evidenceKind: evidenceKind,
        command: expansion.command,
        inputs: inputs,
        timeoutSeconds: timeoutSeconds,
        preset: preset,
      ))
    }
  }

  /// The string members of an array, tokens substituted; `[]` for anything
  /// that is not an array.
  private func substituted(_ value: JSONValue?) -> [String] {
    (value?.arrayValue ?? []).compactMap(\.stringValue).map { part in
      VerifierPresets.substituteTokens(part, slug: slug, variant: variant)
    }
  }
}
