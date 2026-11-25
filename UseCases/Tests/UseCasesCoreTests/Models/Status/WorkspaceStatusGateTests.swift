import Testing
@testable import UseCasesCore

struct WorkspaceStatusGateTests {
  private func gate(
    _ status: VerificationStatus,
    strict: Bool = false,
  ) -> Gate {
    StatusSamples.workspace([StatusSamples.useCase("shop.a", status)]).gate(strict: strict)
  }

  // MARK: - States

  @Test(arguments: [VerificationStatus.failed, .error, .stale])
  func `failed, error and stale block in both modes`(status: VerificationStatus) {
    #expect(gate(status).blocking.map(\.useCase) == ["shop.a"])
    #expect(gate(status).warning.isEmpty)
    #expect(gate(status, strict: true).blocking.map(\.useCase) == ["shop.a"])
  }

  @Test(arguments: [VerificationStatus.incomplete, .unverified])
  func `incomplete and unverified warn, and block under strict`(status: VerificationStatus) {
    #expect(gate(status).passed)
    #expect(gate(status).warning.map(\.useCase) == ["shop.a"])
    #expect(!gate(status, strict: true).passed)
    #expect(gate(status, strict: true).warning.isEmpty)
  }

  @Test(arguments: [VerificationStatus.verified, .draft])
  func `verified use cases and drafts never block or warn`(status: VerificationStatus) {
    for strict in [false, true] {
      let answer = gate(status, strict: strict)

      #expect(answer.passed)
      #expect(answer.warning.isEmpty)
      #expect(answer.isStrict == strict)
    }
  }

  @Test
  func `an entry says its state and that nothing but the state holds it`() throws {
    let entry = try #require(gate(.stale).blocking.first)

    #expect(entry.status == .stale)
    #expect(entry.reason == .status(.stale))
    #expect(entry.heldForApproval == nil)
  }

  @Test
  func `the entries keep the order of the use cases`() {
    let workspace = StatusSamples.workspace([
      StatusSamples.useCase("shop.c", .failed),
      StatusSamples.useCase("shop.b", .unverified),
      StatusSamples.useCase("shop.a", .stale),
    ])

    let answer = workspace.gate(strict: false)

    #expect(answer.blocking.map(\.useCase) == ["shop.c", "shop.a"])
    #expect(answer.warning.map(\.useCase) == ["shop.b"])
  }

  @Test
  func `a route that does not gate never reaches the gate`() {
    let useCase = StatusSamples.useCase(
      "shop.a",
      .verified,
      routes: [
        StatusSamples.route("unit-tests"),
        StatusSamples.route("extra", status: .failed, gates: false),
      ],
    )

    #expect(StatusSamples.workspace([useCase]).gate(strict: true).passed)
  }

  // MARK: - Sign-off

  @Test
  func `without sign-off required, approvals never gate`() {
    let workspace = StatusSamples.workspace([
      StatusSamples.useCase("shop.a", tier: "critical", approval: .unapproved),
      StatusSamples.useCase("shop.b", approval: .changed),
    ])

    #expect(workspace.gate(strict: true).passed)
    #expect(workspace.gate(strict: true).warning.isEmpty)
  }

  @Test(arguments: [
    ("critical", ApprovalState.unapproved, false, true),
    ("critical", ApprovalState.changed, false, true),
    ("core", ApprovalState.unapproved, false, false),
    ("supporting", ApprovalState.changed, false, false),
    ("core", ApprovalState.unapproved, true, true),
    ("supporting", ApprovalState.unapproved, true, true),
    ("critical", ApprovalState.approved, true, false),
  ])
  func `the sign-off holds a use case by its tier`(
    tier: String,
    approval: ApprovalState,
    strict: Bool,
    blocks: Bool,
  ) {
    let workspace = StatusSamples.workspace(
      [StatusSamples.useCase("shop.a", tier: tier, approval: approval)],
      signOffRequired: true,
    )

    let answer = workspace.gate(strict: strict)
    let isHeld = approval != .approved

    #expect(!answer.blocking.isEmpty == (isHeld && blocks))
    #expect(!answer.warning.isEmpty == (isHeld && !blocks))
  }

  @Test
  func `a use case held only for its sign-off says which kind of hold it is`() throws {
    let workspace = StatusSamples.workspace(
      [
        StatusSamples.useCase("shop.a", tier: "critical", approval: .changed),
        StatusSamples.useCase("shop.b", tier: "core", approval: .unapproved),
      ],
      signOffRequired: true,
    )

    let answer = workspace.gate(strict: false)
    let blocking = try #require(answer.blocking.first)
    let warning = try #require(answer.warning.first)

    #expect(blocking.reason == .notApproved)
    #expect(blocking.heldForApproval == .changed)
    #expect(warning.reason == .notApproved)
    #expect(warning.heldForApproval == .unapproved)
  }

  @Test
  func `a use case that is stale and changed since approved blocks for its state and says both`(
  ) throws {
    let workspace = StatusSamples.workspace(
      [StatusSamples.useCase("shop.a", .stale, tier: "critical", approval: .changed)],
      signOffRequired: true,
    )

    let entry = try #require(workspace.gate(strict: false).blocking.first)

    #expect(entry.reason == .status(.stale))
    #expect(entry.heldForApproval == .changed)
  }

  @Test
  func `a use case is in one list only, blocking before warning`() {
    let workspace = StatusSamples.workspace(
      [StatusSamples.useCase("shop.a", .unverified, tier: "critical", approval: .unapproved)],
      signOffRequired: true,
    )

    let answer = workspace.gate(strict: false)

    #expect(answer.blocking.count == 1)
    #expect(answer.warning.isEmpty)
    #expect(answer.blocking.first?.reason == .notApproved)
  }

  @Test
  func `a draft is never held for its sign-off`() {
    let workspace = StatusSamples.workspace(
      [StatusSamples.useCase("shop.a", .draft, tier: "critical", approval: .unapproved)],
      signOffRequired: true,
    )

    #expect(workspace.gate(strict: true).passed)
    #expect(workspace.gate(strict: true).warning.isEmpty)
  }
}
