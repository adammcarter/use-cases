import Foundation
import Testing

/// The black-box oracle for lifecycle/signals.yml, row
/// `local_results_are_attested`.
struct LifecycleAttestationTests {
  // edge_scan_never_mints_a_key. The keyless tier rests on scan being unable to
  // attest anything, and the only way to see that from outside is that no key
  // file appears where the key would go. Pairing it with verify is what makes
  // the assertion mean something: the absence has to be scan's doing, not the
  // test never reaching the code that mints one.
  @Test
  func `scan mints no run key, and verify does`() async throws {
    let workspace = try await SignalsWorkspace.make()
    #expect(!FileManager.default.fileExists(atPath: workspace.runKeyPath))

    let scanned = try await SignalsWorkspace.scan(workspace)
    #expect(
      !FileManager.default.fileExists(atPath: workspace.runKeyPath),
      "scan minted a run key: a read-only command must not be able to attest",
    )
    #expect(SignalsWorkspace.localStatus(scanned) != "VERIFIED_LOCAL")

    let verified = try await SignalsWorkspace.run(
      workspace,
      ["verify", "--repo", ".", "--row", "probe.core.thing"],
    )
    #expect(verified.isOk == true)
    #expect(
      FileManager.default.fileExists(atPath: workspace.runKeyPath),
      "verify did not mint a run key, so the previous assertion proves nothing",
    )
    let after = try await SignalsWorkspace.scan(workspace)
    #expect(SignalsWorkspace.localStatus(after) == "VERIFIED_LOCAL")
  }

  // golden_real_run. The record verify wrote carries an attestation, and that
  // is what makes it count — not the hashes, which anything can compute.
  @Test
  func `a record verify wrote carries an attestation and reads VERIFIED_LOCAL`()
    async throws
  {
    let verified = try await SignalsWorkspace.verified()
    let attestation = verified.record["run_attestation"]?.stringValue ?? ""
    #expect(
      attestation.hasPrefix("hmac-sha256:"),
      "verify must attest every record it emits",
    )
    #expect(verified.record["status"]?.stringValue == "pass")

    let scanned = try await SignalsWorkspace.scan(verified.workspace)
    #expect(SignalsWorkspace.localStatus(scanned) == "VERIFIED_LOCAL")
    #expect(scanned.at("summary.unattested_local")?.intValue == 0)
  }

  // bad_typed_line. The whole point of the keyless tier: byte-perfect hashes
  // prove nothing, because anything that can read the repo can compute them.
  // Only the run key the tool holds separates a run from a text edit.
  @Test
  func `a hand-written record with byte-perfect hashes reads UNATTESTED_LOCAL`()
    async throws
  {
    let verified = try await SignalsWorkspace.verified()
    try SignalsWorkspace.writeRecord(
      verified.workspace,
      SignalsWorkspace.withoutField(verified.record, "run_attestation"),
    )

    let scanned = try await SignalsWorkspace.scan(verified.workspace)
    #expect(
      SignalsWorkspace.localStatus(scanned) == "UNATTESTED_LOCAL",
      "hashes alone must never buy a green",
    )
    #expect(scanned.at("summary.unattested_local")?.intValue == 1)
    #expect(SignalsWorkspace.evidenceCount(scanned, "local_run") == 0)
    #expect(SignalsWorkspace.claimable(scanned) == false)
  }

  // bad_edited_record. Editing ANY field invalidates the attestation, which is
  // what stops a failure being laundered into a pass after the fact.
  @Test
  func `editing an attested record invalidates it, including a laundered pass`()
    async throws
  {
    let verified = try await SignalsWorkspace.verified()
    try SignalsWorkspace.writeRecord(
      verified.workspace,
      SignalsWorkspace.withField(verified.record, [
        "exit_code": .number(1),
        "status": .string("fail"),
      ]),
    )
    let edited = try await SignalsWorkspace.scan(verified.workspace)
    #expect(SignalsWorkspace.localStatus(edited) == "UNATTESTED_LOCAL")

    // And the direction that actually matters: a laundered pass.
    try SignalsWorkspace.writeRecord(
      verified.workspace,
      SignalsWorkspace.withField(verified.record, [
        "exit_code": .number(0),
        "status": .string("pass"),
        "stdout_sha256": .string("sha256:deadbeef"),
      ]),
    )
    let laundered = try await SignalsWorkspace.scan(verified.workspace)
    #expect(
      SignalsWorkspace.localStatus(laundered) == "UNATTESTED_LOCAL",
      "a record edited to say pass must not read as proven",
    )
  }

  // edge_ledger_from_another_machine. Someone else's run is not your evidence,
  // so a ledger committed by a teammate reads unattested on your machine.
  @Test
  func `a results ledger attested on another machine reads unattested here`()
    async throws
  {
    let verified = try await SignalsWorkspace.verified()
    let scanned = try await SignalsWorkspace.scan(verified.workspace)
    #expect(SignalsWorkspace.localStatus(scanned) == "VERIFIED_LOCAL")

    // Same repo, same ledger, different machine-local run key.
    //
    // The rewrite below re-serialises the record with sorted keys, so this
    // control read comes first: under the ORIGINAL key the rewritten ledger
    // must still verify. Without it the test could pass because the bytes
    // moved rather than because the key did.
    try SignalsWorkspace.writeRecord(verified.workspace, verified.record)
    let rewritten = try await SignalsWorkspace.scan(verified.workspace)
    #expect(
      SignalsWorkspace.localStatus(rewritten) == "VERIFIED_LOCAL",
      "re-serialising the record must not by itself break the attestation",
    )

    let elsewhere = try await SignalsWorkspace.scan(
      verified.workspace,
      environment: ["UC_RUN_KEY_FILE": verified.workspace.path + "/machine-b/run-key"],
    )
    #expect(
      SignalsWorkspace.localStatus(elsewhere) == "UNATTESTED_LOCAL",
      "another machine's attestation must not verify here",
    )
  }
}
