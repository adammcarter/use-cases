import Testing
@testable import UseCasesCore

struct ApprovalStateTests {
  private static let promise = String(repeating: "a", count: 64)

  private func approval(behaviour: String) -> Approval {
    Approval(
      approver: "Sam",
      day: "2026-10-19",
      behaviour: behaviour,
    )
  }

  @Test
  func `a use case never signed off is unapproved`() {
    let state = ApprovalState(
      approval: nil,
      promise: Self.promise,
    )

    #expect(state == .unapproved)
  }

  @Test
  func `a sign-off of the promise as it reads is approved`() {
    let state = ApprovalState(
      approval: approval(behaviour: Self.promise),
      promise: Self.promise,
    )

    #expect(state == .approved)
  }

  @Test(arguments: [
    String(repeating: "b", count: 64),
    String(repeating: "A", count: 64),
    "",
  ])
  func `a sign-off of any other promise is changed`(behaviour: String) {
    let state = ApprovalState(
      approval: approval(behaviour: behaviour),
      promise: Self.promise,
    )

    #expect(state == .changed)
  }
}
