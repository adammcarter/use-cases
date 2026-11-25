import Testing
@testable import UseCasesCore

struct ApprovalTests {
  private static let digest = String(repeating: "ab", count: 32)

  private func approval(
    day: String = "2026-10-11",
    digest: String = Self.digest,
  ) throws -> Approval {
    let members = JSONMembers([
      "by": jsonString("Sam"),
      "on": jsonString(day),
      "behaviour": jsonString(digest),
    ])

    return try Approval(authored: AuthoredObject(authored(members.json), at: "approved"))
  }

  @Test
  func `an approval holds who, when and the fingerprint`() throws {
    let approval = try approval()

    #expect(approval.approver == "Sam")
    #expect(approval.day == "2026-10-11")
    #expect(approval.behaviour == Self.digest)
  }

  @Test(arguments: ["2026-02-30", "yesterday"])
  func `an approval on a day that does not exist is refused`(day: String) {
    #expect(throws: AuthoredShapeError.self) {
      try approval(day: day)
    }
  }

  @Test
  func `an approval missing a field is refused`() {
    #expect(throws: AuthoredShapeError.missing(location: "approved.behaviour")) {
      try Approval(
        authored: AuthoredObject(
          authored(#"{"by":"Sam","on":"2026-10-11"}"#),
          at: "approved",
        ),
      )
    }
  }
}
