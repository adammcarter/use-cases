import Testing
@testable import UseCasesCore

struct YAMLResolvedScalarTests {
  @Test
  func `two number readings of not-a-number agree`() {
    #expect(YAMLResolvedScalar.number(.nan).agrees(with: .number(.nan)))
  }

  @Test(arguments: [
    (YAMLResolvedScalar.integer(.exact(15)), YAMLResolvedScalar.integer(.exact(17))),
    (.integer(.exact(1)), .number(1)),
    (.boolean(true), .boolean(false)),
    (.null, .text),
    (.number(1), .number(2)),
    (.text, .timestamp),
  ])
  func `readings that differ in type or value do not agree`(
    left: YAMLResolvedScalar,
    right: YAMLResolvedScalar,
  ) {
    #expect(!left.agrees(with: right))
  }

  @Test(arguments: [
    YAMLResolvedScalar.null,
    .boolean(true),
    .integer(.exact(3)),
    .number(1.5),
    .text,
  ])
  func `a reading agrees with itself`(reading: YAMLResolvedScalar) {
    #expect(reading.agrees(with: reading))
  }

  @Test(arguments: [
    (YAMLResolvedScalar.null, "null"),
    (.boolean(true), "the boolean true"),
    (.integer(.exact(15)), "the integer 15"),
    (.integer(.tooLarge), "an integer too big for 64 bits"),
    (.number(1000), "the number 1000.0"),
    (.sexagesimal, "a base-60 number"),
    (.timestamp, "a date or time"),
    (.mergeKey, "the merge key"),
    (.valueKey, "the value key"),
    (.text, "text"),
  ])
  func `a reading is named in plain words`(
    reading: YAMLResolvedScalar,
    phrase: String,
  ) {
    #expect(reading.phrase == phrase)
  }
}
