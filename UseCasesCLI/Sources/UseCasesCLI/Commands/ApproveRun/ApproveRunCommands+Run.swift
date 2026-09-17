import Foundation
import UseCasesCore

/// `approve-run`: turn a plugin-minted approval request into a signed token.
///
/// Key custody is the whole guarantee, so nothing here reaches for a key the
/// caller did not name: `--key-file` or `--key-env`, or a WebAuthn assertion
/// the operator's authenticator produced. Every refusal is exit 2, as the
/// TypeScript's are — this command validates its arguments and signs, and has
/// no run to fail against. The argument checks are ``SigningArguments``.
extension ApproveRunCommands {
  static func runSign(_ context: HandlerContext) throws(CommandFailure) -> CommandOutput {
    let command = "showcase.approve_run"
    let arguments: SigningArguments
    switch SigningArguments.validated(command, context.flags) {
    case let .refused(output):
      return output
    case let .value(validated):
      arguments = validated
    }

    let request: JSONObject
    switch readRequest(command, atPath: absolute(arguments.requestPath)) {
    case let .refused(output):
      return output
    case let .value(value):
      request = value
    }

    let token: JSONObject
    switch mintToken(command, arguments, request: request, environment: context.environment) {
    case let .refused(output):
      return output
    case let .value(value):
      token = value
    }
    return try emitted(command, token, arguments)
  }

  /// The token inline, or written to `--out` (`JSON.stringify(token, null, 2)`
  /// and a newline) with its path in place of the token itself.
  private static func emitted(
    _ command: String,
    _ token: JSONObject,
    _ arguments: SigningArguments,
  ) throws(CommandFailure) -> CommandOutput {
    let data = summary(token, decision: arguments.decision, keyIdentifier: arguments.keyIdentifier)
    guard let out = arguments.outPath else {
      var inline = JSONObject([("approval_token", .object(token))])
      for (key, value) in data.pairs {
        inline[key] = value
      }
      return CommandOutput(result: result(command, inline), exitCode: 0)
    }
    let outPath = absolute(out)
    do throws(FileAccessError) {
      try NodeFile.writeText("\(JSONWriter.encodePretty(.object(token)))\n", atPath: outPath)
    } catch {
      throw CommandFailure(error)
    }
    var written = JSONObject([("approval_token_path", .string(outPath))])
    for (key, value) in data.pairs {
      written[key] = value
    }
    return CommandOutput(result: result(command, written), exitCode: 0)
  }

  /// `{ jti, decision, key_id, credential_id, assurance_method,
  /// assurance_tier }`, each member left out when the token has none — as
  /// `undefined` is left out of the TypeScript's JSON.
  private static func summary(
    _ token: JSONObject,
    decision: String,
    keyIdentifier: String?,
  ) -> JSONObject {
    var data = JSONObject()
    data["jti"] = token["jti"]
    data["decision"] = .string(decision)
    data["key_id"] = keyIdentifier.map(JSONValue.string)
    if token["signature"]?["alg"] == .string("webauthn") {
      data["credential_id"] = token["signature"]?["credential_id"]
    }
    data["assurance_method"] = token["assurance_method"]
    data["assurance_tier"] = token["assurance_tier"]
    return data
  }

  /// The signed token, or the refusal that stopped it.
  private static func mintToken(
    _ command: String,
    _ arguments: SigningArguments,
    request: JSONObject,
    environment: [String: String],
  ) -> CommandStep<JSONObject> {
    if let assertionPath = arguments.assertionPath {
      switch readAssertion(command, atPath: absolute(assertionPath)) {
      case let .refused(output):
        return .refused(output)
      case let .value(assertion):
        return .value(ApprovalTokens.buildWebAuthnToken(
          request: request,
          decision: arguments.decision,
          assertion: assertion,
        ))
      }
    }
    let privateKeyPEM: String
    switch readPrivateKey(command, arguments, environment: environment) {
    case let .refused(output):
      return .refused(output)
    case let .value(pem):
      privateKeyPEM = pem
    }
    do throws(ShowcaseError) {
      return try .value(ApprovalTokens.sign(
        request: request,
        decision: arguments.decision,
        privateKeyPEM: privateKeyPEM,
        keyIdentifier: arguments.keyIdentifier ?? "",
        assuranceMethod: arguments.assuranceMethod,
      ))
    } catch {
      return .refused(CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: "approve_run.sign_failed",
          message: "could not sign the approval token: \(signFailureDetail(error))",
        ),
        exitCode: 2,
      ))
    }
  }

  /// node's own detail for a key it cannot decode. The TypeScript lets
  /// OpenSSL's message through `createPrivateKey`, and the port refuses
  /// non-ed25519 material itself (the row 4c divergence), so it reports the
  /// decoder text node gives for input that is no key at all.
  private static func signFailureDetail(_ error: ShowcaseError) -> String {
    error == .invalidPrivateKey ? Ed25519KeyMaterial.decoderFailureDetail : error.message
  }

  /// `loadPrivateKey`: the file, else the variable, else the custody refusal.
  private static func readPrivateKey(
    _ command: String,
    _ arguments: SigningArguments,
    environment: [String: String],
  ) -> CommandStep<String> {
    if let keyFile = arguments.keyFile {
      do throws(FileAccessError) {
        return try .value(NodeFile.readText(atPath: absolute(keyFile)))
      } catch {
        return .refused(CommandOutput(
          result: ErrorEnvelope.make(
            command: command,
            code: "approve_run.key_unreadable",
            message: "could not read --key-file: \(error.message)",
          ),
          exitCode: 2,
        ))
      }
    }
    if let keyEnvironment = arguments.keyEnvironment {
      let pem = environment[keyEnvironment] ?? ""
      guard !JavaScriptString.trim(pem).isEmpty else {
        return .refused(CommandOutput(
          result: ErrorEnvelope.make(
            command: command,
            code: "approve_run.key_env_empty",
            message: "env var \(keyEnvironment) is empty or unset",
          ),
          exitCode: 2,
        ))
      }
      return .value(pem)
    }
    return .refused(CommandOutput(
      result: ErrorEnvelope.make(
        command: command,
        code: "approve_run.no_key",
        message: "no signing key: pass --key-file <path> (0600, outside the agent's scope) or "
          + "--key-env <VAR>. The key must be one the in-session agent cannot read — that is "
          + "what makes the approval unforgeable.",
      ),
      exitCode: 2,
    ))
  }

  /// The request must parse and name the v1 request schema.
  private static func readRequest(
    _ command: String,
    atPath path: String,
  ) -> CommandStep<JSONObject> {
    let value: JSONValue
    switch readJSON(
      command,
      atPath: path,
      code: "approve_run.request_unreadable",
      flag: "--request",
    ) {
    case let .refused(output):
      return .refused(output)
    case let .value(parsed):
      value = parsed
    }
    guard let object = value.objectValue,
          object["approval_request_schema"] == .string("ucase-approval-request-v1")
    else {
      return .refused(CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: "approve_run.request_malformed",
          message: "--request is not a ucase-approval-request-v1 object.",
        ),
        exitCode: 2,
      ))
    }
    return .value(object)
  }

  /// `loadWebAuthnAssertion`: four base64url strings, or the malformed
  /// refusal.
  private static func readAssertion(
    _ command: String,
    atPath path: String,
  ) -> CommandStep<JSONObject> {
    let value: JSONValue
    switch readJSON(
      command,
      atPath: path,
      code: "approve_run.webauthn_assertion_unreadable",
      flag: "--webauthn-assertion",
    ) {
    case let .refused(output):
      return .refused(output)
    case let .value(parsed):
      value = parsed
    }
    let members = ["credential_id", "authenticator_data", "client_data_json", "signature"]
    guard let object = value.objectValue,
          members.allSatisfy({ member in object[member]?.stringValue != nil })
    else {
      return .refused(CommandOutput(
        result: ErrorEnvelope.make(
          command: command,
          code: "approve_run.webauthn_assertion_malformed",
          message: "--webauthn-assertion must be JSON with credential_id, authenticator_data, "
            + "client_data_json, and signature base64url fields.",
        ),
        exitCode: 2,
      ))
    }
    return .value(object)
  }

  private static func readJSON(
    _ command: String,
    atPath path: String,
    code: String,
    flag: String,
  ) -> CommandStep<JSONValue> {
    let text: String
    do throws(FileAccessError) {
      text = try NodeFile.readText(atPath: path)
    } catch {
      return .refused(unreadable(command, code: code, flag: flag, detail: error.message))
    }
    do throws(SchemaError) {
      return try .value(JavaScriptPropertyOrder.reordered(JSONParser.parse(text)))
    } catch {
      return .refused(unreadable(command, code: code, flag: flag, detail: error.message))
    }
  }

  private static func unreadable(
    _ command: String,
    code: String,
    flag: String,
    detail: String,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(
        command: command,
        code: code,
        message: "could not read/parse \(flag): \(detail)",
      ),
      exitCode: 2,
    )
  }

  /// The envelope carries the working directory as its workspace, because the
  /// command has no workspace of its own.
  private static func result(
    _ command: String,
    _ data: JSONObject,
  ) -> CliResult {
    CliResult.make(
      command: command,
      data: .object(data),
      isSuccessful: true,
      isComplete: true,
      diagnostics: [],
      workspaceRoot: FileManager.default.currentDirectoryPath,
    )
  }

  private static func absolute(_ path: String) -> String {
    WorkspacePath.absolute(path, relativeTo: FileManager.default.currentDirectoryPath)
  }
}
