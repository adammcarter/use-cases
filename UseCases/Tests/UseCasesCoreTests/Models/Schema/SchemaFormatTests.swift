import Testing
@testable import UseCasesCore

struct SchemaFormatTests {
  @Test(arguments: [
    "2026-10-11",
    "2026-01-01",
    "2026-12-31",
    "2026-02-28",
    "2024-02-29",
    "2000-02-29",
    "2026-04-30",
    "1999-09-30",
    "0001-01-01",
    "9999-12-31",
  ])
  func `a real calendar date is a date`(text: String) {
    #expect(SchemaFormat.date.isValid(text))
  }

  @Test(arguments: [
    "0000-01-01",
    "0000-12-31",
    "0000-02-29",
    "2026-02-30",
    "2026-02-29",
    "2100-02-29",
    "1900-02-29",
    "2026-04-31",
    "2026-06-31",
    "2026-09-31",
    "2026-11-31",
    "2026-13-01",
    "2026-00-10",
    "2026-10-00",
    "2026-10-32",
    "",
    "yesterday",
    "2026-1-1",
    "26-10-11",
    "20261011",
    "2026/10/11",
    "2026-10-11 ",
    "2026-10-11\n",
    "2026-10-11T00:00:00Z",
    "+026-10-11",
    "2026-W41-1",
    "２０２６-10-11",
    "2026-١٠-11",
    "2026-10-1a",
  ])
  func `anything else is not a date`(text: String) {
    #expect(!SchemaFormat.date.isValid(text))
  }
}
