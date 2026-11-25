import Testing
@testable import UseCasesCore

struct StatusJudgeApprovalTests {
  private func promise(of fixture: StatusFixture) throws -> String {
    let loaded = try fixture.workspace.loaded()
    let useCase = try #require(loaded.useCases.first)

    return try PromiseFingerprinter().fingerprint(
      of: PromiseFingerprintInput(
        definition: useCase.definition,
        identifier: useCase.identifier,
      ),
    )
  }

  /// The sample definitions with the use case signed off at this fingerprint.
  private func approved(at behaviour: String) -> String {
    FreshnessSamples.definitions()
      + "    approved:\n      by: Sam\n      \"on\": \"2026-10-19\"\n"
      + "      behaviour: \(behaviour)\n"
  }

  @Test
  func `a use case nobody signed off is unapproved`() throws {
    let fixture = try StatusFixture()

    let useCase = try fixture.useCase()

    #expect(useCase.approval == .unapproved)
    #expect(useCase.approver == nil)
    #expect(useCase.approvedOn == nil)
  }

  @Test
  func `a sign-off of the promise as it reads is approved, and says who and when`() throws {
    let fixture = try StatusFixture()
    try fixture.rewrite(approved(at: promise(of: fixture)))

    let useCase = try fixture.useCase()

    #expect(useCase.approval == .approved)
    #expect(useCase.approver == "Sam")
    #expect(useCase.approvedOn == "2026-10-19")
  }

  @Test
  func `changing the promise after the sign-off reads changed`() throws {
    let fixture = try StatusFixture()
    let signed = try approved(at: promise(of: fixture))

    try fixture.rewrite(
      signed.replacingOccurrences(
        of: "Readable at night.",
        with: "Readable all day.",
      ),
    )

    #expect(try fixture.useCase().approval == .changed)
  }

  @Test
  func `changing how it is proven keeps the approval`() throws {
    let fixture = try StatusFixture()
    let signed = try approved(at: promise(of: fixture))

    try fixture.rewrite(
      signed.replacingOccurrences(
        of: "steps: [Check it.]",
        with: "steps: [Check it on staging.]",
      ),
    )

    #expect(try fixture.useCase().approval == .approved)
  }

  @Test
  func `the setting that requires sign-off is read from the root`() throws {
    let required = try StatusFixture(
      root: "schema_version: 1\nroot: true\nprefix: app\nsign_off: required\n",
    )
    let free = try StatusFixture()

    #expect(try required.status().signOffRequired)
    #expect(try !free.status().signOffRequired)
  }

  @Test
  func `the gate holds an unapproved use case only where sign-off is required`() throws {
    let required = try StatusFixture(
      root: "schema_version: 1\nroot: true\nprefix: app\nsign_off: required\n",
    )
    let free = try StatusFixture()
    try required.record("manual")
    try required.record("unit-tests")
    try free.record("manual")
    try free.record("unit-tests")

    let held = try required.status().gate(strict: false)
    let unheld = try free.status().gate(strict: false)

    #expect(held.warning.map(\.useCase) == ["app.toggle"])
    #expect(held.warning.first?.heldForApproval == .unapproved)
    #expect(unheld.warning.isEmpty)
    #expect(unheld.passed)
  }
}
