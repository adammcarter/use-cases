import Testing
@testable import UseCasesTransformers

struct GoModuleTests {
  private func module(_ text: String) throws -> GoModule {
    let folder = try TemporaryFolder()

    try folder.write(
      "go.mod",
      text,
    )

    return try GoModule(
      modFile: folder.absolute("go.mod"),
      reader: ReportFile(),
    )
  }

  @Test
  func `the module path is the second word of the module line`() throws {
    #expect(try module("// c\nmodule example.com/shop\n\ngo 1.22\n").path == "example.com/shop")
  }

  @Test
  func `a go mod with no module line is refused`() {
    #expect(throws: TransformerFailure.self) {
      try module("go 1.22\n")
    }
    #expect(throws: TransformerFailure.self) {
      try module("module\n")
    }
  }

  @Test
  func `a missing go mod is refused and named`() throws {
    let folder = try TemporaryFolder()

    #expect(throws: TransformerFailure.reportUnreadable(
      path: folder.absolute("go.mod"),
      reason: "go.mod not found",
    )) {
      try GoModule(
        modFile: folder.absolute("go.mod"),
        reader: ReportFile(),
      )
    }
  }

  @Test(arguments: [
    ("example.com/shop", ""),
    ("example.com/shop/cart", "cart"),
    ("example.com/shop/cart/tax", "cart/tax"),
  ])
  func `a package of the module is a folder below its root`(
    package: String,
    folder: String,
  ) throws {
    #expect(try module("module example.com/shop\n").folder(ofPackage: package) == folder)
  }

  @Test(arguments: ["example.com/shopping", "example.com", "other.org/shop", ""])
  func `a package of another module has no folder`(package: String) throws {
    #expect(try module("module example.com/shop\n").folder(ofPackage: package) == nil)
  }
}
