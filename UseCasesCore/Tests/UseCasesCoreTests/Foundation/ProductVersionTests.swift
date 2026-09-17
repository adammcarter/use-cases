import Testing
@testable import UseCasesCore

/// Product identity is frozen by ADR 0007 decision 8: every CLI and MCP envelope
/// reports it, so the Swift port must emit byte-identical values to TypeScript.
struct ProductVersionTests {
  @Test
  func `reports the public product name`() {
    #expect(ProductVersion.productName == "@adammcarter/use-cases")
  }

  @Test
  func `reports the version the TypeScript build reports`() {
    #expect(ProductVersion.version == "0.7.0")
  }

  @Test
  func `defaults an unconfigured workspace component to use-cases`() {
    #expect(ProductVersion.defaultComponentIdentifier == "use-cases")
  }

  @Test
  func `the default component identifier is itself canonical`() {
    #expect(CanonicalIdentifier.isValid(ProductVersion.defaultComponentIdentifier))
  }

  @Test
  func `version info bundles the name and the version`() {
    let info = ProductVersion.versionInfo()
    #expect(info.name == ProductVersion.productName)
    #expect(info.version == ProductVersion.version)
  }

  @Test
  func `no surface leaks the pre-rename product name`() {
    let surfaces = [
      ProductVersion.productName,
      ProductVersion.defaultComponentIdentifier,
    ]
    let leaking = surfaces.filter { surface in
      surface.lowercased().contains("ucm")
    }

    #expect(leaking.isEmpty)
  }
}
