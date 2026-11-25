import Testing
@testable import UseCasesCore

struct DefinitionFileNameTests {
  @Test(arguments: ["login.yml", "login.yaml", "a.b.yml", ".yml", "x y.yaml", "caf\u{E9}.yml"])
  func `a lower-case yml or yaml ending is a definition`(name: String) {
    #expect(DefinitionFileName(name) == .definition)
  }

  @Test(
    arguments: [
      ("ui.YML", "ui.yml"),
      ("ui.Yaml", "ui.yaml"),
      ("ui.yAML", "ui.yaml"),
      ("ui.YAML", "ui.yaml"),
      ("ui.yMl", "ui.yml"),
      ("Ui.Name.YML", "Ui.Name.yml"),
      ("caf\u{E9}.YML", "caf\u{E9}.yml"),
      (".YML", ".yml"),
    ],
  )
  func `any other casing of the ending is wrong, and names the lower-case spelling`(
    name: String,
    renamed: String,
  ) {
    #expect(DefinitionFileName(name) == .wrongCase(renamed: renamed))
  }

  @Test(
    arguments: [
      "", ".", "yml", "yaml", "login.yml.bak", "login.txt", "login.yml ", "login.ymll", "login.yam",
      "login.", "README", "login.y\u{FF4D}l", "login.\u{212A}ml", "login.yml\u{301}", "notes.json",
    ],
  )
  func `any other name is not YAML`(name: String) {
    #expect(DefinitionFileName(name) == .notYAML)
  }
}
