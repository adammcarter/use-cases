import Testing
import UseCasesCore

struct ProductVersionTests {
  @Test
  func `the current build reports contract 1 and store 1`() {
    let version = ProductVersion.current

    #expect(version.contract == 1)
    #expect(version.store == 1)
    #expect(!version.release.isEmpty)
  }
}
