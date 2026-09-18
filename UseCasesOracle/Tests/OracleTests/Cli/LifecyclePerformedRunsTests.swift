import Foundation
import Testing

/// The black-box oracle for lifecycle/signals.yml, row `performed_runs_count`.
struct LifecyclePerformedRunsTests {
  static let passing = ["/bin/sh", "-c", "exit 0"]

  // edge_same_row_driven_twice. Driving one behaviour twice must not report two
  // proofs — otherwise the acceptance claim inflates with repetition, which is
  // exactly the dishonest number this row exists to prevent.
  @Test
  func `one row driven twice is reported once`() async throws {
    let workspace = try await SignalsWorkspace.make()

    let first = try await SignalsWorkspace.drive(workspace, key: "first", argv: Self.passing)
    #expect(first.isOk == true)
    let afterOne = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(afterOne, "performed_run") == 1)
    #expect(SignalsWorkspace.claimable(afterOne) == true)

    let second = try await SignalsWorkspace.drive(workspace, key: "second", argv: Self.passing)
    #expect(second.isOk == true)
    let afterTwo = try await SignalsWorkspace.scan(workspace)
    #expect(
      SignalsWorkspace.evidenceCount(afterTwo, "performed_run") == 1,
      "driving the same row twice inflated the claim",
    )
    #expect(afterTwo.at("acceptance_claim.proven")?.intValue == 1)
  }

  // bad_self_reported, the control: a record with no --perform proves nothing,
  // so the number above is the tool's own execution and not merely a record.
  // golden_driven. The claim reads the ledger of behaviour actually driven.
  @Test
  func `a tool-executed passing run proves its row and counts as performed_run`()
    async throws
  {
    let workspace = try await SignalsWorkspace.make()
    let driven = try await SignalsWorkspace.drive(
      workspace,
      key: "golden",
      argv: Self.passing,
    )
    #expect(driven.isOk == true)

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(scanned, "performed_run") == 1)
    #expect(scanned.at("acceptance_claim.proven")?.intValue == 1)
    #expect(SignalsWorkspace.claimable(scanned) == true)
  }

  // bad_failing_run_proves_nothing. Driving a behaviour and watching it fail is
  // still a performed run — it just is not proof that the behaviour holds.
  @Test
  func `a failing run does not prove the behaviour holds`() async throws {
    let workspace = try await SignalsWorkspace.make()
    _ = try await SignalsWorkspace.drive(
      workspace,
      key: "failing",
      argv: ["/bin/sh", "-c", "exit 1"],
    )

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(scanned, "performed_run") == 0)
    #expect(SignalsWorkspace.claimable(scanned) == false)
  }

  // bad_voided_record_does_not_count. Voiding is how a mistake is corrected in
  // an append-only ledger, so the claim has to follow the correction.
  @Test
  func `a voided record stops counting`() async throws {
    let workspace = try await SignalsWorkspace.make()
    let driven = try await SignalsWorkspace.drive(
      workspace,
      key: "voidable",
      argv: Self.passing,
    )
    let before = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(before, "performed_run") == 1)

    let aggregate = try #require(driven.data.at("event.aggregate_id")?.stringValue)
    let eventIdentifier = try #require(driven.data.at("event.event_id")?.stringValue)
    let voided = try await SignalsWorkspace.run(workspace, [
      "evidence", "void", "--repo", ".", "--evidence", aggregate,
      "--expected-head", eventIdentifier, "--reason", "recorded against the wrong row",
    ])
    #expect(voided.isOk == true)
    let after = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(after, "performed_run") == 0)
  }

  // edge_row_edited_after_the_run. This tier decays like every other: a run
  // proved the row as it was, not the row as it now is.
  @Test
  func `editing the row invalidates the run that proved the old one`() async throws {
    let workspace = try await SignalsWorkspace.make()
    _ = try await SignalsWorkspace.drive(workspace, key: "before-edit", argv: Self.passing)
    let before = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(before, "performed_run") == 1)

    let feature = try workspace.directory.readFile("use-cases/probe.yml")
    try workspace.directory.writeFile(
      "use-cases/probe.yml",
      contents: feature.replacingOccurrences(
        of: "title: The thing works",
        with: "title: The thing works, retitled",
      ),
    )
    let after = try await SignalsWorkspace.scan(workspace)
    #expect(
      SignalsWorkspace.evidenceCount(after, "performed_run") == 0,
      "a run recorded against a since-edited row must stop counting",
    )
  }

  // edge_unbound_row_cannot_be_driven_into_proof. Driving something and naming
  // an unbound row must not manufacture coverage the row never had.
  @Test
  func `an unbound row cannot be proven by driving something and naming it`()
    async throws
  {
    let workspace = try await SignalsWorkspace.make(bind: false)
    _ = try await SignalsWorkspace.drive(workspace, key: "unbound", argv: Self.passing)

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.rows(scanned).first?["status"]?.stringValue == "UNBOUND")
    #expect(scanned.at("acceptance_claim.proven")?.intValue == 0)
    #expect(SignalsWorkspace.claimable(scanned) == false)
  }

  // bad_observed_command_is_not_a_run. A record may name a full command line
  // and still be nothing more than a claim. What counts is that the TOOL ran
  // it, which is why the producer and verifier matter as much as the argv.
  @Test
  func `a command the tool merely observed is not a run it executed`() async throws {
    let workspace = try await SignalsWorkspace.make()
    let driven = try await SignalsWorkspace.drive(
      workspace,
      key: "observed",
      argv: Self.passing,
    )
    let before = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(before, "performed_run") == 1)

    // Same argv, downgraded to something an agent merely watched.
    let ledgerPath = try #require(driven.data["ledger_path"]?.stringValue)
    let stored = try workspace.directory.readFile(ledgerPath)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    let event = try OracleJson.parse(String(#require(stored.split(separator: "\n").first)))
    // `method.type` is the tell, not the argv: replay reads structured_command
    // as "the tool executed this", and anything else as a report or an
    // observation. A human who WATCHED a command and wrote down its argv lands
    // here — a real observation, and still not a run the tool performed.
    let method = try #require(event.at("payload.method"))
    var payload = try #require(event["payload"]?.objectValue)
    payload["method"] = .object([
      "type": .string("observed"),
      "executable": method["executable"] ?? .null,
      "argv": method["argv"] ?? .null,
    ])
    let downgraded = SignalsWorkspace.withField(event, ["payload": .object(payload)])
    try workspace.directory.writeFile(ledgerPath, contents: downgraded.encoded + "\n")

    let observed = try await SignalsWorkspace.scan(workspace)
    #expect(
      SignalsWorkspace.evidenceCount(observed, "performed_run") == 0,
      "argv alone must not make a claim into a run",
    )
    #expect(SignalsWorkspace.claimable(observed) == false)
  }

  @Test
  func `a self-reported record proves nothing`() async throws {
    let workspace = try await SignalsWorkspace.make()
    let recorded = try await SignalsWorkspace.run(workspace, [
      "evidence", "record", "--repo", ".", "--use-case", "probe.core.thing",
      "--summary", "I ran it and it definitely worked.",
    ])
    #expect(recorded.isOk == true)

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.evidenceCount(scanned, "performed_run") == 0)
    #expect(SignalsWorkspace.claimable(scanned) == false)
  }
}
