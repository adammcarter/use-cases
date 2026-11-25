import Testing
@testable import UseCasesCore

struct LocalFileSystemListingTests {
  /// Names of 1 to 250 characters, three of each length at most, 600 in all: the sizes that put
  /// a directory entry at the very end of the buffer `readdir` reads from, where a copy of the
  /// whole fixed-size name field would read past it.
  private static func names() -> [String] {
    (0 ..< 600).map { index in
      let letter = ["a", "b", "c"][index / 250]

      return String(repeating: letter, count: 1 + index % 250)
    }
  }

  @Test
  func `six hundred files with names of every length up to 250 are listed and round-trip`()
    throws
  {
    let directory = try TemporaryDirectory()
    let names = Self.names()

    for name in names {
      try directory.write("many/\(name)")
    }

    let entries = try LocalFileSystem().entries(in: directory.location(of: "many"))

    #expect(Set(names).count == 600)
    #expect(entries.count == 600)
    #expect(Set(entries.map(\.name)) == Set(names))
    #expect(entries.allSatisfy { $0.isNameUTF8 && $0.kind == .file })
  }
}
