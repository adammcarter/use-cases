import Foundation
import UseCasesCore

/// `keygen`: print the keypair, or write it to `--out` — never inside
/// `--repo`, the private key owner-only. A setup command, so it resolves no
/// workspace; `--repo` only guards `--out`.
extension KeygenCommands {
  static let privateKeyFilename = "ci-signing-key.pem"
  static let publicKeyFilename = "ci-signing-key.pub.pem"

  static let privateKeyWarning = "The private key is a CI secret: store it ONLY in your CI secret "
    + "store (never commit it, never write it into the repo). Commit / distribute only the "
    + "public key."

  static func run(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "markers.keygen"
    let runtime = MarkerRuntime(context: context)
    let repositoryRoot = runtime.resolved(runtime.string("repo") ?? ".")

    let provider = runtime.string("ci")
    if let provider, provider != "github" {
      return MarkersCommands.invalidArguments(
        command,
        "Unsupported --ci provider: \(provider) (supported: github).",
      )
    }

    let keypair = SigningKeyGeneration.generate()
    let snippet = provider == nil ? nil : githubSnippet

    guard let out = runtime.truthy("out") else {
      var data = JSONObject([
        ("algorithm", .string("ed25519")),
        ("private_key", .string(keypair.privatePEM)),
        ("public_key", .string(keypair.publicPEM)),
        ("warning", .string(privateKeyWarning)),
      ])
      data["ci_snippet"] = snippet.map(JSONValue.string)
      return success(command: command, data: data, repositoryRoot: repositoryRoot)
    }

    let outDirectory = runtime.resolved(out)
    guard !WorkspacePath.isContained(root: repositoryRoot, child: outDirectory) else {
      return CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: "keygen.out_inside_repo",
          message: "--out (\(outDirectory)) is inside --repo (\(repositoryRoot)). The private key "
            + "must never be written into the repo tree — choose a directory outside it.",
        ),
        exitCode: 4,
      )
    }
    let (privatePath, publicPath) = try write(keypair, to: outDirectory)
    var data = JSONObject([
      ("algorithm", .string("ed25519")),
      ("private_key_path", .string(privatePath)),
      ("public_key_path", .string(publicPath)),
      ("public_key", .string(keypair.publicPEM)),
      ("warning", .string(privateKeyWarning)),
    ])
    data["ci_snippet"] = snippet.map(JSONValue.string)
    return success(command: command, data: data, repositoryRoot: repositoryRoot)
  }

  /// The private key owner read/write only; it is never echoed once written.
  private static func write(
    _ keypair: SigningKeypair,
    to outDirectory: String,
  ) throws(CommandFailure) -> (privatePath: String, publicPath: String) {
    let privatePath = NodePath.join(outDirectory, privateKeyFilename)
    let publicPath = NodePath.join(outDirectory, publicKeyFilename)
    do throws(FileAccessError) {
      try NodeFile.makeDirectories(atPath: outDirectory)
      try NodeFile.writeText(keypair.privatePEM, atPath: privatePath, mode: 0o600)
      try NodeFile.writeText(keypair.publicPEM, atPath: publicPath)
    } catch {
      throw CommandFailure(error)
    }
    return (privatePath, publicPath)
  }

  private static func success(
    command: String,
    data: JSONObject,
    repositoryRoot: String,
  ) -> CommandOutput {
    CommandOutput(
      result: CliResult.make(command: command, data: .object(data), workspaceRoot: repositoryRoot),
      exitCode: 0,
    )
  }

  /// A release-workflow job that signs with a key from a repository secret and
  /// authenticates through OIDC; no long-lived token is embedded.
  static let githubSnippet = [
    "# .github/workflows/release.yml — sign use-cases proofs in CI",
    "#",
    "# 1. Add the PRIVATE key PEM as a repository secret named UCM_CI_SIGNING_KEY",
    "#    (Settings -> Secrets and variables -> Actions -> New repository secret).",
    "# 2. Commit the PUBLIC key (ci-signing-key.pub.pem) so scan/validate-ledger can verify.",
    "#",
    "permissions:",
    "  contents: read",
    "  id-token: write   # OIDC — no long-lived token needed",
    "",
    "jobs:",
    "  prove:",
    "    runs-on: ubuntu-latest",
    "    steps:",
    "      - uses: actions/checkout@v4",
    "      - name: Mint signed proofs",
    "        env:",
    "          UCM_CI_SIGNING_KEY: ${{ secrets.UCM_CI_SIGNING_KEY }}",
    "        run: |",
    "          use-cases prove --all --trusted-ci \\",
    "            --signing-key-env UCM_CI_SIGNING_KEY \\",
    "            --key-id ci-key-1",
    "",
  ].joined(separator: "\n")
}
