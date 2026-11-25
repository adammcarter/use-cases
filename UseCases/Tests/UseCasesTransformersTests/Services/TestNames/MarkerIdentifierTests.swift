import Testing
@testable import UseCasesTransformers

struct MarkerIdentifierTests {
  @Test
  func `an id with a route names a validation`() throws {
    let identifier = try #require(MarkerIdentifier("demo.math.add#unit-tests.adds-numbers"))

    #expect(identifier.useCase == "demo.math.add")
    #expect(identifier.route == "unit-tests")
    #expect(identifier.binding == "adds-numbers")
  }

  @Test
  func `an id with no route names an implementation`() throws {
    let identifier = try #require(MarkerIdentifier("demo#core"))

    #expect(identifier.useCase == "demo")
    #expect(identifier.route == nil)
    #expect(identifier.binding == "core")
  }

  @Test(arguments: [
    "",
    "demo",
    "#binding",
    "demo#",
    "demo#a.b.c",
    "demo#a..b",
    "demo#.b",
    "demo#b.",
    "Demo#b",
    "demo#B",
    "demo#-b",
    "demo#b-",
    "demo.#b",
    ".demo#b",
    "demo..x#b",
    "de mo#b",
    "demo#b#c",
    "demo#a_b",
  ])
  func `text that is not spelled as a marker id is refused`(text: String) {
    #expect(MarkerIdentifier(text) == nil)
  }

  @Test(arguments: ["a#b", "a1.b2#c3.d4", "x-y.z-w#p-q.r-s", "0#0.0"])
  func `segments are lower case letters, digits and inner hyphens`(text: String) {
    #expect(MarkerIdentifier(text) != nil)
  }
}
