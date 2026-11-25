import Testing
@testable import UseCasesCore

struct ApprovalStamperTests {
  private let fixture: BatchFixture
  private let kim: ApproverName

  init() throws {
    fixture = try BatchFixture()
    kim = try ApproverName(validating: "Kim")
  }

  private func toggle() throws -> LoadedUseCase {
    try #require(
      fixture.loaded().useCases.first { useCase in
        useCase.identifier.text == "app.dark.toggle"
      },
    )
  }

  private func promise(of useCase: LoadedUseCase) throws -> String {
    try PromiseFingerprinter().fingerprint(
      of: PromiseFingerprintInput(
        definition: useCase.definition,
        identifier: useCase.identifier,
      ),
    )
  }

  @Test
  func `a use case is signed with the name, the day and the fingerprint of its promise`() throws {
    let useCase = try toggle()
    let expected = try promise(of: useCase)

    let signed = try ApprovalStamper().signed(
      useCase.definition,
      as: useCase.identifier,
      by: kim,
      on: "2026-10-20",
    )

    #expect(
      signed.approval == Approval(
        approver: "Kim",
        day: "2026-10-20",
        behaviour: expected,
      ),
    )
    #expect(expected.count == 64)
    #expect(signed.approved(nil) == useCase.definition)
  }

  @Test
  func `a use case already approved as it reads keeps the approval it has`() throws {
    let useCase = try toggle()
    let earlier = try Approval(
      approver: "Sam",
      day: "2026-01-02",
      behaviour: promise(of: useCase),
    )
    let definition = useCase.definition.approved(earlier)

    let signed = try ApprovalStamper().signed(
      definition,
      as: useCase.identifier,
      by: kim,
      on: "2026-10-20",
    )

    #expect(signed == definition)
  }

  @Test
  func `a promise that changed since it was approved is approved again`() throws {
    let useCase = try toggle()
    let stale = Approval(
      approver: "Sam",
      day: "2026-01-02",
      behaviour: String(repeating: "0", count: 64),
    )

    let signed = try ApprovalStamper().signed(
      useCase.definition.approved(stale),
      as: useCase.identifier,
      by: kim,
      on: "2026-10-20",
    )

    #expect(signed.approval?.approver == "Kim")
    #expect(try signed.approval?.behaviour == promise(of: useCase))
  }

  @Test
  func `a promise that cannot be fingerprinted is refused with the use case's id`() throws {
    let useCase = try toggle()
    let stamper = ApprovalStamper(
      fingerprinter: MockPromiseFingerprinting(failing: .missingIntent),
    )

    #expect(
      throws: ApprovalStampingError.unfingerprintable(
        identifier: "app.dark.toggle",
        reason: "missingIntent",
      ),
    ) {
      try stamper.signed(
        useCase.definition,
        as: useCase.identifier,
        by: kim,
        on: "2026-10-20",
      )
    }
  }

  @Test
  func `the refusal says which use case and why`() {
    let error = ApprovalStampingError.unfingerprintable(
      identifier: "a.b.c",
      reason: "no intent",
    )

    #expect(error.message == "the promise of 'a.b.c' cannot be signed off: no intent")
  }
}
