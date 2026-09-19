/// Why a verification context hash could not be taken.
public enum VerificationContextHashError: Error, Equatable, Sendable {
  /// A declared input or the lockfile could not be read for a reason other than
  /// not existing, raised as node's `readFileSync` raises it.
  case fileAccess(FileAccessError)
  /// A resolved timeout is NaN or an infinity, which canonical JSON refuses.
  case nonFiniteNumber

  public var code: String {
    switch self {
    case let .fileAccess(error): error.code
    case .nonFiniteNumber: "non_finite_number"
    }
  }
}

/// The verification context hash (verificationContextHash.ts): binds a proof to
/// HOW it was verified — the row's verification_policy, the resolved verifiers
/// it demands, the bytes of every declared input and the repo lockfile — so a
/// weakened or deleted acceptance test drops the row out of FRESH.
public enum VerificationContextHash {
  /// The algorithm id embedded beside the hash in proof events.
  public static let identifier = "ucase-verification-context-hash-v1"

  /// The lockfile hashed when the caller names none.
  public static let defaultLockfileName = "pnpm-lock.yaml"

  /// The sentinel for a declared input or lockfile that does not exist. It is
  /// never a `sha256:` value, so absent and present-but-empty differ.
  static let absentContent = "absent"

  /// Resolve the row's verifiers, then hash them: the single entry point both
  /// `prove` (to embed) and `scan` (to re-derive) use.
  public static func computeForRow(
    slug: String,
    verificationPolicy: JSONValue?,
    rootDirectory: String,
    files: some TextFileReading,
    lockfileName: String? = nil,
    workspaceVerifiers: ResolvedWorkspaceVerifiers = ResolvedWorkspaceVerifiers(),
  ) throws(VerificationContextHashError) -> String {
    let verifiers = VerifierResolver.resolveRowVerifiers(
      slug: slug,
      verificationPolicy: verificationPolicy,
      workspace: workspaceVerifiers,
    )
    return try compute(
      verificationPolicy: verificationPolicy,
      verifiers: verifiers,
      rootDirectory: rootDirectory,
      files: files,
      lockfileName: lockfileName,
    )
  }

  /// `sha256(canonical_json({ verification_policy, verifiers, inputs,
  /// lockfile_sha256 }))` over already-resolved verifiers.
  public static func compute(
    verificationPolicy: JSONValue?,
    verifiers: [VerifierResolution],
    rootDirectory: String,
    files: some TextFileReading,
    lockfileName: String? = nil,
  ) throws(VerificationContextHashError) -> String {
    let lockfile = lockfileName ?? defaultLockfileName
    var inputs: [JSONValue] = []
    for path in declaredInputs(verifiers) {
      try inputs.append(.object(JSONObject([
        ("path", .string(path)),
        (
          "content_sha256",
          .string(contentMarker(path, rootDirectory: rootDirectory, files: files))
        ),
      ])))
    }
    let material = try JSONValue.object(JSONObject([
      ("verification_policy", verificationPolicy ?? .null),
      ("verifiers", .array(VerifierResolver.sortedByIdentifier(verifiers).map(canonicalVerifier))),
      ("inputs", .array(inputs)),
      (
        "lockfile_sha256",
        .string(contentMarker(lockfile, rootDirectory: rootDirectory, files: files))
      ),
    ]))
    do throws(CodeUnitCanonicalJSONError) {
      return try CodeUnitCanonicalJSON.sha256(material)
    } catch {
      throw .nonFiniteNumber
    }
  }

  private static func declaredInputs(_ verifiers: [VerifierResolution]) -> [String] {
    var paths = OrderedStringSet()
    for case let .resolved(verifier) in verifiers {
      for input in verifier.inputs {
        paths.insert(input)
      }
    }
    return paths.sortedMembers
  }

  /// An absolute path verbatim — NOT normalized — and anything else joined
  /// onto the root as `path.join` joins it.
  private static func readPath(
    _ path: String,
    rootDirectory: String,
  ) -> String {
    NodePath.isAbsolute(path) ? path : NodePath.join(rootDirectory, path)
  }

  private static func contentMarker(
    _ path: String,
    rootDirectory: String,
    files: some TextFileReading,
  ) throws(VerificationContextHashError) -> String {
    let text: String?
    do throws(FileAccessError) {
      text = try files.readText(atPath: readPath(path, rootDirectory: rootDirectory))
    } catch {
      throw .fileAccess(error)
    }
    guard let text else {
      return absentContent
    }
    return MarkerDigest.sha256(text)
  }

  /// Only the fields that define HOW verification runs: never `source`,
  /// `inputs` or `preset`.
  private static func canonicalVerifier(_ verification: VerifierResolution) -> JSONValue {
    switch verification {
    case let .resolved(verifier):
      var object = JSONObject([
        ("verifier_id", .string(verifier.verifierIdentifier)),
        ("status", .string("resolved")),
        ("kind", .string("script")),
        ("evidence_kind", .string(verifier.evidenceKind)),
        ("command", .array(verifier.command.map(JSONValue.string))),
      ])
      object["timeout_seconds"] = verifier.timeoutSeconds.map(JSONValue.number)
      return .object(object)
    case let .blocked(verifier):
      return verifier.jsonValue
    }
  }
}
