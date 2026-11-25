import Testing
@testable import UseCasesCore

struct LinkContributionKindTests {
  @Test
  func `a link kind follows the source the core found`() {
    #expect(LinkContributionKind(source: .marker) == .marker)
    #expect(LinkContributionKind(source: .manual) == .manual)
  }

  @Test
  func `a transformer kind is written as transformer`() {
    #expect(LinkContributionKind.transformer.rawValue == "transformer")
  }
}
