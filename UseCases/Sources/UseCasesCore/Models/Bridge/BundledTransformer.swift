/// The transformers that ship with the build (`docs/transformers/README.md`), by name.
enum BundledTransformer {
  /// Every name a bridge entry may use without a path. The core knows no tool: it knows only
  /// which names exist.
  static let names: Set<String> = [
    "junit",
    "go-test-json",
    "cargo-test",
    "swift-test",
    "swift-testing",
    "cucumber-messages",
    "exit-code",
    "test-names",
  ]
}
