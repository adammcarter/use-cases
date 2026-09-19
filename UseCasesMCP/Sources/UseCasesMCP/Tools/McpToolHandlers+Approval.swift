import UseCasesCore

/// `showcase_request_approval`.
///
/// F3: an agent may only ASK. The tool mints a PLUGIN-owned, single-use
/// approval request bound to the live run — the nonce and expiry are minted
/// here, never by the caller — which a real human signs out of band with
/// `use-cases approve-run` using a key outside the agent's reach. Nothing is
/// appended, and `complete` stays false because asking does not finish the act.
extension McpToolHandlers {
  public static func showcaseRequestApproval(
    _ arguments: JSONObject,
    _ environment: McpEnvironment,
  ) throws(McpToolFailure) -> CliResult {
    let command = "showcase.request-approval"
    let workspace: ResolvedWorkspaceContext
    switch try McpWorkspace.resolve(
      arguments: arguments,
      command: command,
      environment: environment,
    ) {
    case let .refused(result):
      return result
    case let .resolved(resolved):
      workspace = resolved
    }

    guard let runIdentifier = McpToolArguments.string(arguments, "run") else {
      return McpErrorEnvelope.make(
        command: command,
        code: "cli_invalid_arguments",
        message: "Missing run.",
        environment: environment,
      )
    }
    if let unsafe = unsafeIdentifier(command, "run", runIdentifier, environment) {
      return unsafe
    }

    let status = try replayed(workspace, runIdentifier)
    let events = try ledgerEvents(workspace, runIdentifier)
    let start = events.first { event in
      event["event_type"] == .string("run_started")
    }
    let finish = events.reversed().first { event in
      event["event_type"] == .string("run_finished")
    }
    let plan = start?["payload"]?["plan"]
    let request = finish == nil ? nil : mintedRequest(workspace, runIdentifier)

    let data = JSONObject([
      ("schema_version", .number(1)),
      ("decision_required", .bool(true)),
      ("trusted_confirmation_required", .bool(true)),
      ("run_id", .string(runIdentifier)),
      ("plan_hash", plan?["plan_content_hash"] ?? .null),
      ("finish_event_id", finish?["event_id"] ?? .null),
      ("known_gaps", status.knownGaps),
      // The out-of-band signing request. Write it to a file and hand it to a
      // human.
      ("approval_request", request.map(JSONValue.object) ?? .null),
      (
        "approval_request_schema",
        request == nil ? .null : .string("ucase-approval-request-v1")
      ),
      // How a HUMAN signs it, in their own shell with an out-of-scope key. An
      // agent driving the CLI cannot fake the token this produces.
      ("suggested_signer_command", request == nil ? .null : signerCommand),
      ("status", status.jsonValue),
    ])
    return envelope(command, .object(data), workspace, isComplete: status.isComplete)
  }

  private static let signerCommand = JSONValue.array([
    .string("use-cases"),
    .string("approve-run"),
    .string("--request"),
    .string("<request-file>"),
    .string("--key-file"),
    .string("<out-of-scope-key>"),
    .string("--key-id"),
    .string("<keyring-key-id>"),
    .string("--json"),
  ])

  private static func ledgerEvents(
    _ workspace: ResolvedWorkspaceContext,
    _ runIdentifier: String,
  ) throws(McpToolFailure) -> [JSONValue] {
    do throws(ShowcaseError) {
      return try ShowcaseLedger.read(context: workspace, runIdentifier: runIdentifier).events
    } catch {
      throw McpToolFailure(error)
    }
  }

  /// A run that is not yet in an approvable state mints nothing rather than
  /// failing the call: the caller is told it cannot ask yet by the null.
  private static func mintedRequest(
    _ workspace: ResolvedWorkspaceContext,
    _ runIdentifier: String,
  ) -> JSONObject? {
    do throws(ShowcaseError) {
      let binding = try ApprovalBinding.binding(
        context: workspace,
        runIdentifier: runIdentifier,
      )
      return try ApprovalTokens().mintRequest(binding: binding)
    } catch {
      return nil
    }
  }
}
