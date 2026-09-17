import Foundation
import UseCasesCore

/// The key material a signed approval is verified against, and where it came
/// from (the `TrustResolvers` / `ApprovalTokenBundle` pair in
/// packages/cli/src/commands/showcase.ts).
///
/// A workspace-pinned `approval_trust` anchor is authoritative: flags can only
/// NARROW it, never add to it, and `pinnedKeyIdentifiers` records the ids it
/// allows so a token signed by anyone else is refused before the core sees it.
/// Without a pin, `--keyring` and `--public-key` still work — the additive,
/// backward-compatible path — but say so through an advisory diagnostic.
struct ShowcaseTrustMaterial {
  let resolvers: ShowcaseTrustResolvers
  let diagnostics: [Diagnostic]
  /// The ids a pinned anchor allows, keyed by their code units as JavaScript
  /// compares them; nil when the trust is caller-supplied.
  let pinnedKeyIdentifiers: Set<[UInt8]>?

  /// `callerSuppliedTrustDiagnostic`.
  static let callerSupplied = Diagnostic(
    code: "showcase.approval_trust_anchor_caller_supplied",
    severity: .warning,
    message: "Approval-token verification is using caller-supplied trust material because "
      + "use-cases.yml has no approval_trust pin.",
  )

  /// `loadTrustResolvers`: the pinned anchor narrowed by any flag, else the
  /// flags' own material, else nil — which leaves a signed approval reading
  /// pending, as replay fails closed.
  static func load(
    flags: ParsedFlags,
    workspace: ResolvedWorkspaceContext,
  ) throws(CommandFailure) -> ShowcaseTrustMaterial? {
    if let pinned = try pinnedKeyring(workspace) {
      return try narrowed(pinned, flags)
    }
    if let keyringPath = ShowcaseCommands.string(flags["keyring"]) {
      let keyring = try loadKeyring(
        atPath: absolute(keyringPath),
        code: "showcase.approval_keyring_unreadable",
        flag: "--keyring",
      )
      return ShowcaseTrustMaterial(
        resolvers: resolvers(of: keyring),
        diagnostics: [callerSupplied],
        pinnedKeyIdentifiers: nil,
      )
    }
    guard let publicKeyPath = ShowcaseCommands.string(flags["publicKey"]) else {
      return nil
    }
    let pem = try publicKeyPEM(atPath: absolute(publicKeyPath))
    return ShowcaseTrustMaterial(
      // The operator nominated this single key as the trusted human signer, so
      // it carries the tier that meets the floor; per-key downgrades and
      // revocations live in a keyring.
      resolvers: ShowcaseTrustResolvers(
        publicKeyResolver: MarkerCommandInputs.singleKeyResolver(publicKey: pem),
        tierResolver: { _, _ in .trustedHostUserPresence },
        webAuthnCredentialResolver: { _, _ in nil },
      ),
      diagnostics: [callerSupplied],
      pinnedKeyIdentifiers: nil,
    )
  }

  /// `loadApprovalTokenBundle`: the parsed `--approval-token` with the trust
  /// that may verify it, or nil when no token was supplied.
  static func tokenBundle(
    flags: ParsedFlags,
    workspace: ResolvedWorkspaceContext,
  ) throws(CommandFailure) -> (token: JSONValue, trust: ShowcaseTrustMaterial)? {
    guard let tokenPath = ShowcaseCommands.string(flags["approvalToken"]) else {
      return nil
    }
    let token = try readJSON(
      atPath: absolute(tokenPath),
      code: "showcase.approval_token_unreadable",
      flag: "--approval-token",
    )
    guard let trust = try load(flags: flags, workspace: workspace) else {
      throw CommandFailure(
        code: "showcase.approval_key_required",
        message: "verifying --approval-token needs trusted key material: pin approval_trust in "
          + "use-cases.yml or pass --keyring <path> / --public-key <path>.",
      )
    }
    let signature = token["signature"]
    if signature?["alg"] == .string("webauthn"), trust.pinnedKeyIdentifiers == nil {
      throw CommandFailure(
        code: "showcase.approval_webauthn_unpinned",
        message: "webauthn approval tokens require a workspace-pinned approval_trust credential; "
          + "caller-supplied keyrings cannot introduce WebAuthn trust.",
      )
    }
    let anchor = signature?["key_id"]?.stringValue ?? signature?["credential_id"]?.stringValue
    if let anchor, let pinned = trust.pinnedKeyIdentifiers,
       !pinned.contains(Array(anchor.utf8))
    {
      throw CommandFailure(
        code: "showcase.approval_trust_anchor_unpinned",
        message: "approval token signer '\(anchor)' is not in pinned approval_trust.",
      )
    }
    return (token, trust)
  }

  /// `loadPinnedApprovalTrustKeyring`: the workspace's own anchor, built from
  /// a keyring file, an inline keyring and inline public keys in that order.
  private static func pinnedKeyring(_ workspace: ResolvedWorkspaceContext)
    throws(CommandFailure) -> Keyring?
  {
    guard let pinned = workspace.approvalTrust else {
      return nil
    }
    var keys: [JSONValue] = []
    if let path = pinned.keyringPath {
      do throws(KeyringError) {
        keys += try Keyring.loadKeys(
          filePath: WorkspacePath.absolute(path, relativeTo: workspace.workspaceRoot),
        )
      } catch {
        throw CommandFailure(
          code: "showcase.approval_trust_keyring_unreadable",
          message: "could not read approval_trust.keyring_path: \(error.message)",
        )
      }
    }
    if let inline = pinned.keyring {
      keys += inline["keys"]?.arrayValue ?? []
    }
    if let publicKeys = pinned.publicKeys {
      keys += publicKeys
    }
    guard !keys.isEmpty else {
      return nil
    }
    return try keyring(from: keys, sourcePath: "use-cases.yml#/approval_trust")
  }

  /// `selectPinnedTrustResolvers`: a flag may only pick out keys the anchor
  /// already holds, and picking none leaves trust that knows no key at all.
  private static func narrowed(
    _ pinned: Keyring,
    _ flags: ParsedFlags,
  ) throws(CommandFailure) -> ShowcaseTrustMaterial {
    let identifiers = keyIdentifiers(of: pinned)
    if let keyringPath = ShowcaseCommands.string(flags["keyring"]) {
      let requested = try loadKeyring(
        atPath: absolute(keyringPath),
        code: "showcase.approval_keyring_unreadable",
        flag: "--keyring",
      )
      let wanted = keyIdentifiers(of: requested)
      let selected = pinned.keys.filter { key in
        wanted.contains(Array(identifier(of: key).utf8))
      }
      return selected.isEmpty
        ? empty(identifiers)
        : ShowcaseTrustMaterial(
          resolvers: resolvers(of: Keyring(keys: selected)),
          diagnostics: [],
          pinnedKeyIdentifiers: identifiers,
        )
    }
    if let publicKeyPath = ShowcaseCommands.string(flags["publicKey"]) {
      let pem = try publicKeyPEM(atPath: absolute(publicKeyPath))
      let selected = pinned.keys.filter { key in
        guard case let .ed25519(entry) = key else {
          return false
        }
        return Ed25519KeyMaterial.isSamePublicKey(entry.publicKey, pem)
      }
      return selected.isEmpty
        ? empty(identifiers)
        : ShowcaseTrustMaterial(
          resolvers: resolvers(of: Keyring(keys: selected)),
          diagnostics: [],
          pinnedKeyIdentifiers: identifiers,
        )
    }
    return ShowcaseTrustMaterial(
      resolvers: resolvers(of: pinned),
      diagnostics: [],
      pinnedKeyIdentifiers: identifiers,
    )
  }

  /// `emptyTrustResolvers`: pinned, but narrowed to nothing.
  private static func empty(_ identifiers: Set<[UInt8]>) -> ShowcaseTrustMaterial {
    ShowcaseTrustMaterial(
      resolvers: ShowcaseTrustResolvers(
        publicKeyResolver: { _, _ in nil },
        tierResolver: { _, _ in nil },
        webAuthnCredentialResolver: { _, _ in nil },
      ),
      diagnostics: [],
      pinnedKeyIdentifiers: identifiers,
    )
  }

  private static func resolvers(of keyring: Keyring) -> ShowcaseTrustResolvers {
    ShowcaseTrustResolvers(
      publicKeyResolver: keyring.publicKeyResolver(),
      tierResolver: keyring.maxAssuranceTierResolver(),
      webAuthnCredentialResolver: keyring.webAuthnCredentialResolver(),
    )
  }

  /// `keyIds`: a webauthn entry is known by its credential id, an ed25519 one
  /// by its key id.
  private static func keyIdentifiers(of keyring: Keyring) -> Set<[UInt8]> {
    Set(keyring.keys.map { key in
      Array(identifier(of: key).utf8)
    })
  }

  private static func identifier(of key: KeyringKey) -> String {
    switch key {
    case let .ed25519(entry): entry.keyIdentifier
    case let .webAuthn(entry): entry.credentialIdentifier
    }
  }

  /// `keyringFromKeys`: the selected keys re-parsed as a keyring, so the same
  /// schema check applies.
  private static func keyring(
    from keys: [JSONValue],
    sourcePath: String?,
  ) throws(CommandFailure) -> Keyring {
    do throws(KeyringError) {
      return try Keyring.parse(
        .object(JSONObject([
          ("keyring_schema_id", .string("ucase-public-key-registry-v1")),
          ("keys", .array(keys)),
        ])),
        sourcePath: sourcePath,
      )
    } catch {
      throw CommandFailure(
        code: "showcase.approval_trust_keyring_unreadable",
        message: "could not read approval_trust.keyring_path: \(error.message)",
      )
    }
  }

  private static func loadKeyring(
    atPath path: String,
    code: String,
    flag: String,
  ) throws(CommandFailure) -> Keyring {
    do throws(KeyringError) {
      return try Keyring.load(filePath: path)
    } catch {
      throw CommandFailure(code: code, message: "could not read \(flag): \(error.message)")
    }
  }

  /// `readPublicKeyFlag`: read it, then decode it. An unreadable file and a
  /// file that is no key share the `public_key.invalid` code, as node's
  /// `createPublicKey` failure does.
  private static func publicKeyPEM(atPath path: String) throws(CommandFailure) -> String {
    let pem: String
    do throws(FileAccessError) {
      pem = try NodeFile.readText(atPath: path)
    } catch {
      throw CommandFailure(
        code: "public_key.invalid",
        message: "could not read/parse --public-key: \(error.message)",
      )
    }
    guard Ed25519KeyMaterial.isPublicKey(pem: pem) else {
      throw CommandFailure(
        code: "public_key.invalid",
        message: "could not read/parse --public-key: "
          + Ed25519KeyMaterial.decoderFailureDetail,
      )
    }
    return pem
  }

  private static func readJSON(
    atPath path: String,
    code: String,
    flag: String,
  ) throws(CommandFailure) -> JSONValue {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: path)
    } catch {
      throw CommandFailure(
        code: code,
        message: "could not read/parse \(flag): \(error.message)",
      )
    }
    do throws(SchemaError) {
      return try JavaScriptPropertyOrder.reordered(JSONParser.parse(text))
    } catch {
      throw CommandFailure(
        code: code,
        message: "could not read/parse \(flag): \(error.message)",
      )
    }
  }

  /// A flag's path, resolved against the working directory as node's
  /// `resolve(process.cwd(), value)` does.
  private static func absolute(_ path: String) -> String {
    WorkspacePath.absolute(path, relativeTo: FileManager.default.currentDirectoryPath)
  }
}
