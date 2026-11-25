import Testing
@testable import UseCasesCore

struct RootOnlySettingTests {
  @Test
  func `the root-only settings are freshness, discovery and sign_off`() {
    #expect(RootOnlySetting.allCases.map(\.key) == ["freshness", "discovery", "sign_off"])
  }
}
