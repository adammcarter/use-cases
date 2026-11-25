import Testing
@testable import UseCasesCore

struct RunIdentifierShortenerTests {
  private static let first = "0192f0c4e5a17c3e9b04d2f61a8c3b57"
  private static let second = "0192f0c4e5b27c3e9b04d2f61a8c3b58"
  private static let third = "0192f0c4e5b27c3f9b04d2f61a8c3b59"

  @Test
  func `a run alone shows its first 8 digits`() {
    #expect(RunIdentifierShortener(runs: [Self.first]).shortened(Self.first) == "0192f0c4")
  }

  // @use-case:store.run-ids#swift-tests.short-ids
  @Test
  func `each of several close runs shows the shortest prefix no other run shares`() {
    let shortener = RunIdentifierShortener(runs: [Self.third, Self.first, Self.second])

    #expect(shortener.shortened(Self.first) == "0192f0c4e5a")
    #expect(shortener.shortened(Self.second) == "0192f0c4e5b27c3e")
    #expect(shortener.shortened(Self.third) == "0192f0c4e5b27c3f")
  }

  // @use-case:end store.run-ids#swift-tests.short-ids

  @Test
  func `the same run listed twice is still one run`() {
    let shortener = RunIdentifierShortener(runs: [Self.first, Self.first])

    #expect(shortener.shortened(Self.first) == "0192f0c4")
  }

  @Test
  func `a run the store does not hold shows its first 8 digits`() {
    #expect(RunIdentifierShortener(runs: [Self.second]).shortened(Self.first) == "0192f0c4")
  }
}
