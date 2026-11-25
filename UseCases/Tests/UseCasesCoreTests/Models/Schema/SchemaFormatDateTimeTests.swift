import Testing
@testable import UseCasesCore

/// The verdicts of the schema validator the design is checked with (`jsonschema` with its format
/// checker) for RFC 3339 `date-time`.
struct SchemaFormatDateTimeTests {
  @Test(arguments: [
    "2026-09-25T12:34:56.123Z",
    "2026-09-25t12:34:56z",
    "2026-09-25T12:34:56Z",
    "2024-02-29T00:00:00Z",
    "2026-09-25T12:34:56+01:00",
    "2026-09-25T12:34:56-00:00",
    "2026-09-25T00:00:00+23:59",
    "2026-09-25T12:34:56.0Z",
    "2026-09-25T12:34:56.1234567890123Z",
    "0001-01-01T00:00:00Z",
    "2026-09-25T12:34:56+00:00",
    "9999-12-31T23:59:59Z",
  ])
  func `an RFC 3339 time is a date-time`(text: String) {
    #expect(SchemaFormat.dateTime.isValid(text))
  }

  @Test(arguments: [
    "",
    "2026-09-25",
    "2026-09-25T12:34:60Z",
    "2026-09-25T12:34:61Z",
    "2026-12-31T23:59:60Z",
    "2026-09-25T23:59:60.5+00:00",
    "2026-02-29T00:00:00Z",
    "2026-09-25T24:00:00Z",
    "2026-09-25T12:34Z",
    "2026-09-25T12:34:56",
    "2026-09-25 12:34:56Z",
    "2026-09-25T12:34:56.Z",
    "2026-09-31T00:00:00Z",
    "0000-01-01T00:00:00Z",
    "2026-09-25T12:34:56+24:00",
    "2026-09-25T12:34:56+00:60",
    "2026-13-01T00:00:00Z",
    "2026-09-25T12:60:00Z",
    "\u{FF12}\u{FF10}\u{FF12}\u{FF16}-09-25T12:34:56Z",
    "2026-09-25T12:34:56+0000",
    "2026-09-25T12:34:56\n",
    "2026-09-25T12:34:56Z\n",
    "2026-09-25T12:34:5Z",
    "2026-09-25T12:34:56.1",
    "yesterday",
  ])
  func `anything else is not a date-time`(text: String) {
    #expect(!SchemaFormat.dateTime.isValid(text))
  }
}
