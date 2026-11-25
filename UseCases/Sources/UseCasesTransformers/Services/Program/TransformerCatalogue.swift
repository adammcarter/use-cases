/// The bundled transformers by name (`docs/transformers/README.md`).
enum TransformerCatalogue {
  /// Every bundled name, in the catalogue's order.
  static let names = [
    "junit",
    "go-test-json",
    "cargo-test",
    "swift-test",
    "swift-testing",
    "cucumber-messages",
    "exit-code",
    "test-names",
  ]

  static func transformer(named name: String) -> RegisteredTransformer? {
    switch name {
    case "junit": .results(JUnitTransformer())
    case "go-test-json": .results(GoTestJSONTransformer())
    case "cargo-test": .results(CargoTestTransformer())
    case "swift-test": .results(SwiftTestTransformer())
    case "swift-testing": .results(SwiftTestingTransformer())
    case "cucumber-messages": .results(CucumberMessagesTransformer())
    case "exit-code": .results(ExitCodeTransformer())
    case "test-names": .links(TestNamesTransformer())
    default: nil
    }
  }
}
