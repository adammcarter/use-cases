import Foundation
import UseCasesCore

/// What a marker command reads beyond its workspace (packages/cli/src/commands/
/// markers.ts helpers): its flags, the working directory paths resolve
/// against, and the environment the TypeScript reads as `process.env` — the
/// run key's home, signing keys, CI identity — with git run in it and git's
/// stderr kept in order.
struct MarkerRuntime {
  let context: HandlerContext

  var flags: ParsedFlags {
    context.flags
  }

  var environment: [String: String] {
    context.environment
  }

  var gitRunner: GitProcessRunner {
    GitProcessRunner(environment: environment, standardErrorLog: context.standardError)
  }

  /// `os.homedir()` reads `$HOME` first.
  var runKeyLocation: RunKeyLocation {
    RunKeyLocation(
      environment: environment,
      homeDirectory: environment["HOME"] ?? NSHomeDirectory(),
    )
  }

  /// A string flag's value, or nil when absent.
  func string(_ key: String) -> String? {
    guard case let .string(text) = flags[key] else {
      return nil
    }
    return text
  }

  /// A string flag's value when JavaScript reads it as truthy: present and
  /// not empty.
  func truthy(_ key: String) -> String? {
    guard let text = string(key), !text.isEmpty else {
      return nil
    }
    return text
  }

  func isOn(_ key: String) -> Bool {
    flags[key] == .boolean(true)
  }

  /// An integer flag's value. The parser has already dropped a value that is
  /// not a finite number; a fractional one is dropped here, as the core takes
  /// whole line numbers only.
  func integer(_ key: String) -> Int? {
    guard case let .number(number) = flags[key] else {
      return nil
    }
    return Int(exactly: number)
  }

  /// `resolve(process.cwd(), value)`.
  func resolved(_ value: String) -> String {
    WorkspacePath.absolute(value, relativeTo: FileManager.default.currentDirectoryPath)
  }

  /// `markerPaths`: the product root and both ledgers, each flag resolved
  /// against the working directory when truthy, else its default.
  func paths(_ workspace: ResolvedWorkspaceContext) -> MarkerPaths {
    MarkerPaths(
      productRoot: truthy("productRoot").map(resolved) ?? workspace.workspaceRoot,
      bindingsPath: truthy("bindings").map(resolved)
        ?? NodePath.join(workspace.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: truthy("proofs").map(resolved)
        ?? NodePath.join(workspace.dataRoot, ".use-cases", "proofs.jsonl"),
    )
  }

  /// `markerKeyConfigured`: `--keyring` or `--public-key`, truthy.
  var isKeyConfigured: Bool {
    truthy("keyring") != nil || truthy("publicKey") != nil
  }

  /// `markerPublicKeyResolver`: the keyring when given (it wins), else the one
  /// `--public-key`, else a resolver that knows no key. The public key file is
  /// read before it is checked, so an unreadable file throws node's own error.
  func publicKeyResolver() throws(CommandFailure) -> PublicKeyResolver {
    if let keyring = truthy("keyring") {
      do throws(KeyringError) {
        return try Keyring.publicKeyResolver(fromFile: resolved(keyring))
      } catch {
        throw CommandFailure(code: error.code, message: error.message)
      }
    }
    guard let keyPath = truthy("publicKey") else {
      return { _, _ in nil }
    }
    let pem: String
    do throws(FileAccessError) {
      pem = try NodeFile.readText(atPath: resolved(keyPath))
    } catch {
      throw CommandFailure(error)
    }
    guard Ed25519KeyMaterial.isPublicKey(pem: pem) else {
      throw Self.keyMaterialFailure(kind: "public", origin: keyPath)
    }
    return MarkerCommandInputs.singleKeyResolver(publicKey: pem)
  }

  /// `markerSigningKey`: the PEM in the variable `--signing-key-env` names,
  /// nil when either is empty, refused when it is not a private key.
  func signingKey() throws(CommandFailure) -> ProveSigningKey? {
    guard let name = truthy("signingKeyEnv"),
          let pem = environment[name], !pem.isEmpty
    else {
      return nil
    }
    guard Ed25519KeyMaterial.isPrivateKey(pem: pem) else {
      throw Self.keyMaterialFailure(kind: "signing", origin: "$\(name)")
    }
    return ProveSigningKey(privateKeyPEM: pem, keyIdentifier: string("keyId") ?? "trusted-ci")
  }

  /// The GitHub-shaped producer block, read off the environment.
  var producer: ProveProducer {
    ProveProducer(
      runIdentifier: environment["GITHUB_RUN_ID"],
      repository: environment["GITHUB_REPOSITORY"],
      commit: environment["GITHUB_SHA"],
    )
  }

  /// `detectCiAuthority(process.env)`.
  var detectedAuthority: JSONValue {
    ProveCommand.authorityRecord(CiAuthority.detect(environment: environment))
  }

  /// `keyMaterialError`. node's detail is OpenSSL's text for the failure; the
  /// port reports the decoder's, which is what node gives for text that is no
  /// key at all.
  private static func keyMaterialFailure(
    kind: String,
    origin: String,
  ) -> CommandFailure {
    CommandFailure(
      code: kind == "signing" ? "signing_key.invalid" : "public_key.invalid",
      message: "The \(kind) key (\(origin)) is not a valid PEM key — expected a PKCS8 ed25519 "
        + "PEM. See docs/security/key-management.md to generate one. "
        + "(\(Ed25519KeyMaterial.decoderFailureDetail))",
    )
  }
}
