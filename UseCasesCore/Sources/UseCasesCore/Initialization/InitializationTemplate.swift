/// The project shapes `use-cases init` can scaffold, in the TypeScript's order.
public enum InitializationTemplate: String, CaseIterable, Sendable {
  case generic
  case javaScriptVitest = "js-vitest"
  case pythonPytest = "python-pytest"
  case goTest = "go-test"
}
