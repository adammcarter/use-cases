import Testing
@testable import UseCasesCore

/// The YAML writer against `stringify(value, { lineWidth: 0 })` from the `yaml`
/// package — the call the TypeScript mutation makes — for every scalar style
/// decision, at four nesting depths and as a key.
struct UseCaseFileEmitterTests {
  @Test(arguments: UseCasesGoldenCorpus.emitterCaseNames)
  func `a document is written byte for byte as yaml writes it`(caseName: String) throws {
    let testCase = try UseCasesFixtures.goldenCase(caseName, in: "emitter")
    let document = try #require(JSONParser.parse(UseCasesFixtures.string(testCase, "json"))
      .objectValue)

    let yaml = UseCaseFileEmitter.stringify(document)

    #expect(yaml == testCase["yaml"]?.stringValue)
  }
}
