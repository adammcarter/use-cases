import Testing
@testable import UseCasesTransformers

struct TransformerCatalogueTests {
  @Test
  func `every name in the catalogue has a transformer`() {
    #expect(TransformerCatalogue.names.count == 8)

    for name in TransformerCatalogue.names {
      #expect(TransformerCatalogue.transformer(named: name) != nil)
    }
  }

  @Test(arguments: [
    ("junit", TransformerJob.results),
    ("go-test-json", .results),
    ("cargo-test", .results),
    ("swift-test", .results),
    ("swift-testing", .results),
    ("cucumber-messages", .results),
    ("exit-code", .results),
    ("test-names", .links),
  ])
  func `each transformer does the one job the catalogue gives it`(
    name: String,
    job: TransformerJob,
  ) {
    #expect(TransformerCatalogue.transformer(named: name)?.job == job)
  }

  @Test(arguments: ["", "JUnit", "junit ", "tools/junit", "pytest"])
  func `any other name is no bundled transformer`(name: String) {
    #expect(TransformerCatalogue.transformer(named: name) == nil)
  }
}
