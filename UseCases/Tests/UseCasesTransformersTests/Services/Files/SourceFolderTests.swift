import Testing
@testable import UseCasesTransformers

struct SourceFolderTests {
  @Test
  func `files come in name order, a folder's own files before its subfolders`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "b.txt",
      "",
    )
    try folder.write(
      "a.txt",
      "",
    )
    try folder.write(
      "z/inner.txt",
      "",
    )
    try folder.write(
      "m/inner.txt",
      "",
    )

    #expect(
      SourceFolder(root: folder.path).files(
        matching: "**/*.txt",
        under: "",
      )
        == ["a.txt", "b.txt", "m/inner.txt", "z/inner.txt"],
    )
  }

  @Test(arguments: [".git", ".use-cases", ".build", ".gradle", "node_modules"])
  func `version control, store and dependency folders are skipped at any depth`(
    skipped: String,
  ) throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "kept/a.txt",
      "",
    )
    try folder.write(
      "\(skipped)/hidden.txt",
      "",
    )
    try folder.write(
      "kept/deep/\(skipped)/hidden.txt",
      "",
    )

    #expect(
      SourceFolder(root: folder.path).files(
        matching: "**/*.txt",
        under: "",
      ) == ["kept/a.txt"],
    )
  }

  @Test(arguments: ["build", "target"])
  func `build output is skipped only directly under the folder being searched`(
    name: String,
  ) throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "\(name)/output.txt",
      "",
    )
    try folder.write(
      "com/acme/\(name)/Source.txt",
      "",
    )
    try folder.write(
      "test/\(name)/a.txt",
      "",
    )

    #expect(
      SourceFolder(root: folder.path).files(
        matching: "**/*.txt",
        under: "",
      )
        == ["com/acme/\(name)/Source.txt", "test/\(name)/a.txt"],
    )
  }

  @Test
  func `the top of a search is the folder it is given, not the code root`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "web/build/output.txt",
      "",
    )
    try folder.write(
      "web/src/build/Source.txt",
      "",
    )
    try folder.write(
      "web/src/a.txt",
      "",
    )

    #expect(
      SourceFolder(root: folder.path).files(
        matching: "**/*.txt",
        under: "web",
      )
        == ["web/src/a.txt", "web/src/build/Source.txt"],
    )
  }

  @Test
  func `the pattern is read from the folder searched, and results are workspace paths`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "web/src/a.rs",
      "",
    )
    try folder.write(
      "src/b.rs",
      "",
    )

    let listing = SourceFolder(root: folder.path)

    #expect(listing.files(
      matching: "src/**/*.rs",
      under: "web",
    ) == ["web/src/a.rs"])
    #expect(listing.files(
      matching: "src/**/*.rs",
      under: "",
    ) == ["src/b.rs"])
  }

  @Test
  func `only the files directly in a folder are listed`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "pkg/a_test.go",
      "",
    )
    try folder.write(
      "pkg/b.go",
      "",
    )
    try folder.write(
      "pkg/sub/c_test.go",
      "",
    )

    #expect(
      SourceFolder(root: folder.path).files(directlyIn: "pkg") == ["pkg/a_test.go", "pkg/b.go"],
    )
    #expect(SourceFolder(root: folder.path).files(directlyIn: "missing").isEmpty)
  }

  @Test
  func `the root folder itself can be listed`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "go.mod",
      "",
    )
    try folder.write(
      "pkg/x.go",
      "",
    )

    #expect(SourceFolder(root: folder.path).files(directlyIn: "") == ["go.mod"])
  }
}
