import Foundation
import Testing

//: @use-case:showcase.flow.approval_authority_boundary#blackbox
/// The black-box oracle for showcase/flow.yml, row
/// `approval_authority_boundary`.
struct ShowcaseApprovalBoundaryTests {
  static let humanKey = ShowcaseApproval.ed25519Pem()

  // golden_trusted_confirmation_path.
  @Test
  func `a signed token is the only thing appended as a user approval`() async throws {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await ShowcaseWorkspace.finishedApprovalRun(
      directory,
      seed: "trusted",
    )

    let signed = try await ShowcaseApproval.signTrustedApproval(
      directory,
      run: runIdentifier,
      key: Self.humanKey,
      keyIdentifier: "human-key-1",
    )
    let approved = try await ShowcaseWorkspace.run(directory, [
      "showcase", "approve", "--repo", ".", "--run", runIdentifier,
      "--statement", "User accepts the demonstrated showcase scope.",
      "--approval-token", signed.tokenPath, "--keyring", signed.keyringPath,
    ])
    #expect(approved.exitCode == 0, Comment(rawValue: approved.standardOutput))
    // MCP/an agent can only REQUEST approval; this is the proof the write
    // itself came from the signed path, not a caller asserting it.
    #expect(
      approved.data.at("event.payload.capture_method")?.stringValue
        == "host_signed_approval_token",
    )
    #expect(approved.data.at("event.payload.approver.type")?.stringValue == "user")

    let read = try await ShowcaseWorkspace.status(
      directory,
      run: runIdentifier,
      extra: ["--keyring", signed.keyringPath],
    )
    #expect(read["approval_state"]?.stringValue == "approved")
  }

  // bad_untrusted_approval_event.
  @Test
  func `a raw user approval event appended outside the tool is not honoured`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await ShowcaseWorkspace.finishedApprovalRun(
      directory,
      seed: "forged-approve",
    )
    let finishEvent = try #require(
      try ShowcaseWorkspace.event(directory, run: runIdentifier, ofType: "run_finished"),
    )
    let finishEventIdentifier = try #require(finishEvent["event_id"]?.stringValue)

    let forged = try ShowcaseApproval.appendRawEvent(
      directory,
      run: runIdentifier,
      eventType: "approval_recorded",
      actorType: "user",
      payload: ShowcaseApproval.forgedApprovalPayload(
        decision: "approved",
        statement: "forged approval",
        finishEventIdentifier: finishEventIdentifier,
      ),
    )

    let read = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(
      read["approval_state"]?.stringValue == "pending",
      "an untrusted event must not be honoured as approval",
    )
    let ignored = (read.at("diagnostic_summary.ignored_approval_events")?.arrayValue ?? [])
      .compactMap { entry in
        entry.stringValue
      }
    #expect(
      ignored.contains(forged),
      "the ignored forgery must be named, not silently dropped",
    )
  }

  // bad_untrusted_rejection_event. The boundary is not one-directional: a
  // forged rejection is exactly as unauthorized as a forged approval.
  @Test
  func `a raw user rejection event appended outside the tool is not honoured`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await ShowcaseWorkspace.finishedApprovalRun(
      directory,
      seed: "forged-reject",
    )
    let finishEvent = try #require(
      try ShowcaseWorkspace.event(directory, run: runIdentifier, ofType: "run_finished"),
    )
    let finishEventIdentifier = try #require(finishEvent["event_id"]?.stringValue)

    try ShowcaseApproval.appendRawEvent(
      directory,
      run: runIdentifier,
      eventType: "approval_rejected",
      actorType: "user",
      payload: ShowcaseApproval.forgedApprovalPayload(
        decision: "rejected",
        statement: "forged rejection",
        finishEventIdentifier: finishEventIdentifier,
      ),
    )

    let read = try await ShowcaseWorkspace.status(directory, run: runIdentifier)
    #expect(
      read["approval_state"]?.stringValue == "pending",
      "an untrusted rejection must not be honoured either",
    )
  }

  // edge_scripted_approval_leaves_the_ledger_untouched.
  @Test
  func `a scripted noninteractive user approval is refused and appends nothing`()
    async throws
  {
    let directory = try ShowcaseWorkspace.make(
      approvalPolicy: ShowcaseWorkspace.requireUserApproval,
    )
    let runIdentifier = try await ShowcaseWorkspace.finishedApprovalRun(
      directory,
      seed: "scripted",
    )
    let before = try ShowcaseWorkspace.readEvents(directory, run: runIdentifier).count

    let scripted = try await ShowcaseWorkspace.run(directory, [
      "showcase", "approve", "--repo", ".", "--run", runIdentifier,
      "--statement", "scripted", "--actor", "user",
    ])
    #expect(scripted.isOk == false)
    #expect(
      scripted.envelope.diagnostics.encoded
        .contains("showcase.trusted_user_confirmation_required"),
    )
    #expect(
      try ShowcaseWorkspace.readEvents(directory, run: runIdentifier).count == before,
      "a refused approval must not mutate the ledger",
    )
  }
}

//: @use-case:end showcase.flow.approval_authority_boundary#blackbox
