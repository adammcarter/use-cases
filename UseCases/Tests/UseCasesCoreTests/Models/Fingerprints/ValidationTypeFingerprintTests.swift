import Testing
@testable import UseCasesCore

struct ValidationTypeFingerprintTests {
  @Test(
    arguments: [
      (ValidationType.unit, "unit"),
      (ValidationType.integration, "integration"),
      (ValidationType.contract, "contract"),
      (ValidationType.snapshot, "snapshot"),
      (ValidationType.userInterface, "ui"),
      (ValidationType.e2e, "e2e"),
      (ValidationType.acceptance, "acceptance"),
      (ValidationType.performance, "performance"),
    ],
  )
  func `a built-in type writes the kind it is authored with`(
    row: (type: ValidationType, kind: String),
  ) {
    #expect(row.type.kindName == row.kind)
  }

  @Test
  func `a custom type writes custom`() throws {
    #expect(try ValidationType.custom(name: IdentifierSegment(validating: "x"))
      .kindName == "custom")
  }
}
