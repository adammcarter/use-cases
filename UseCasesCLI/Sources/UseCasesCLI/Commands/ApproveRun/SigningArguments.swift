import UseCasesCore

/// `approve-run`'s arguments once they have been checked, in the order the
/// TypeScript checks them: the request and a way to sign it, then the two
/// flags a WebAuthn assertion excludes, then the decision, then the assurance
/// method. Every refusal is `cli_invalid_arguments` with exit 2.
struct SigningArguments {
  /// The three decisions a token may carry.
  static let decisions = ["approved", "approved_with_known_gaps", "rejected"]
  /// The methods an ed25519 signature may claim; `webauthn` belongs to an
  /// assertion.
  static let ed25519Methods = [
    AssuranceMethod.automation.rawValue,
    AssuranceMethod.sameChannel.rawValue,
    AssuranceMethod.operatingSystemPresence.rawValue,
  ]

  let requestPath: String
  let keyIdentifier: String?
  let assertionPath: String?
  let keyFile: String?
  let keyEnvironment: String?
  let decision: String
  /// The method the token records: the flag's value, or `os_presence`.
  let assuranceMethod: String
  let outPath: String?

  static func validated(
    _ command: String,
    _ flags: ParsedFlags,
  ) -> CommandStep<SigningArguments> {
    let assertionPath = ShowcaseCommands.string(flags["webauthnAssertion"])
    let keyIdentifier = ShowcaseCommands.string(flags["keyId"])
    guard let requestPath = ShowcaseCommands.string(flags["request"]),
          assertionPath != nil || keyIdentifier != nil
    else {
      return .refused(refusal(
        command,
        "Missing --request, or missing --key-id for ed25519 signing.",
      ))
    }
    let keyFile = ShowcaseCommands.string(flags["keyFile"])
    let keyEnvironment = ShowcaseCommands.string(flags["keyEnv"])
    if assertionPath != nil, keyFile != nil || keyEnvironment != nil {
      return .refused(refusal(
        command,
        "--webauthn-assertion packages an authenticator assertion; do not also pass "
          + "--key-file or --key-env.",
      ))
    }
    let decision = ShowcaseCommands.string(flags["decision"]) ?? "approved"
    guard decisions.contains(where: { candidate in
      JavaScriptString.identical(candidate, decision)
    }) else {
      return .refused(refusal(
        command,
        "Unsupported --decision: \(decision) (allowed: \(decisions.joined(separator: ", "))).",
      ))
    }
    let method = ShowcaseCommands.string(flags["assuranceMethod"])
    if let refused = refusedMethod(command, method, isAssertion: assertionPath != nil) {
      return .refused(refused)
    }
    return .value(SigningArguments(
      requestPath: requestPath,
      keyIdentifier: keyIdentifier,
      assertionPath: assertionPath,
      keyFile: keyFile,
      keyEnvironment: keyEnvironment,
      decision: decision,
      assuranceMethod: method ?? AssuranceMethod.operatingSystemPresence.rawValue,
      outPath: ShowcaseCommands.string(flags["out"]),
    ))
  }

  /// An assertion records `webauthn` and nothing else; an ed25519 signature
  /// records any other method the ladder knows.
  private static func refusedMethod(
    _ command: String,
    _ method: String?,
    isAssertion: Bool,
  ) -> CommandOutput? {
    if isAssertion {
      guard let method,
            !JavaScriptString.identical(method, AssuranceMethod.webAuthn.rawValue)
      else {
        return nil
      }
      return refusal(
        command,
        "--webauthn-assertion always records assurance_method webauthn; omit "
          + "--assurance-method or pass webauthn.",
      )
    }
    let effective = method ?? AssuranceMethod.operatingSystemPresence.rawValue
    let recognised = AssuranceMethod.recognised(.string(effective))
    guard recognised == nil || recognised == .webAuthn else {
      return nil
    }
    return refusal(
      command,
      "Unsupported ed25519 --assurance-method: \(effective) "
        + "(allowed: \(ed25519Methods.joined(separator: ", "))).",
    )
  }

  private static func refusal(
    _ command: String,
    _ message: String,
  ) -> CommandOutput {
    CommandOutput(
      result: ErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: message,
      ),
      exitCode: 2,
    )
  }
}
