import Testing
@testable import UseCasesCLI

struct ByteTextTests {
  @Test(arguments: [
    (Int64(0), "0 B"),
    (999, "999 B"),
    (1000, "1.0 KB"),
    (7812, "7.8 KB"),
    (9_960_000, "10 MB"),
    (999_600, "1.0 MB"),
    (450_000_000, "450 MB"),
    (2_500_000_000_000_000, "2500 TB"),
  ])
  func `a size reads in steps of 1000, with one decimal below 10`(
    bytes: Int64,
    text: String,
  ) {
    #expect(ByteText.text(bytes) == text)
  }
}
