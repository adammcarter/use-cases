import Foundation
import Testing
@testable import UseCasesCore

struct RootFinderTests {
  private func finder() -> RootFinder {
    RootFinder(
      fileSystem: LocalFileSystem(),
      settingsLoader: ScopeSettingsLoader(
        fileSystem: LocalFileSystem(),
        settingsReader: MockScopeSettingsReader(),
      ),
    )
  }

  private func workspace() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", "root: true\n")
    try directory.write("services/pay/use-cases.yml", "")
    try directory.write("services/pay/src/deep/file.swift")
    return directory
  }

  @Test(arguments: ["", "services", "services/pay", "services/pay/src/deep"])
  func `the root is found from the root and from any folder below it`(start: String) throws {
    let directory = try workspace()

    let root = try finder().findRoot(from: directory.location(of: start))

    #expect(root.directory == directory.url)
    #expect(root.settings.isRoot)
  }

  @Test
  func `a child scope is passed over on the way up`() throws {
    let directory = try workspace()
    try directory.write("services/pay/src/use-cases.yml", "use_cases_dir: here\n")

    let root = try finder().findRoot(from: directory.location(of: "services/pay/src/deep"))

    #expect(root.directory == directory.url)
  }

  @Test
  func `a nested workspace is found first from inside it`() throws {
    let directory = try workspace()
    try directory.write("vendor/lib/use-cases.yml", "root: true\n")
    try directory.write("vendor/lib/src/a.swift")

    let root = try finder().findRoot(from: directory.location(of: "vendor/lib/src"))

    #expect(root.directory == directory.location(of: "vendor/lib"))
  }

  @Test
  func `the root is read through the configuration reader`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", "root: true\nuse_cases_dir: specs\nexclude: gen/**\n")

    let root = try finder().findRoot(from: directory.url)

    #expect(root.settings.useCasesDirectory.text == "specs")
    #expect(root.settings.excludes.map(\.text) == ["gen/**"])
  }

  @Test
  func `a start spelled through a symlink walks up the real folders`() throws {
    let directory = try workspace()
    let outside = try TemporaryDirectory()
    try outside.symlink("link", to: directory.location(of: "services/pay").path)

    let root = try finder().findRoot(from: outside.location(of: "link"))

    #expect(root.directory == directory.url)
  }

  @Test
  func `no root above is refused with the pinned message`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("services/pay/use-cases.yml", "")
    let start = directory.location(of: "services/pay")

    do throws(RootFindingError) {
      _ = try finder().findRoot(from: start)
      Issue.record("a root was found")
    } catch {
      #expect(error == .noRootFound(startingAt: start))
      #expect(
        error.description
          == "no use-cases.yml with root: true in this folder or any folder above it; "
          + "run `use-cases init`",
      )
    }
  }

  @Test
  func `a folder named use-cases dot yml is not a configuration`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("use-cases.yml", "root: true\n")
    try directory.write("sub/use-cases.yml/inner.txt")

    let root = try finder().findRoot(from: directory.location(of: "sub"))

    #expect(root.directory == directory.url)
  }

  @Test
  func `a configuration that cannot be read on the way up stops the search`() throws {
    let directory = try workspace()
    try directory.write("services/use-cases.yml", "invalid\n")

    let start = directory.location(of: "services/pay")

    do throws(RootFindingError) {
      _ = try finder().findRoot(from: start)
      Issue.record("a root was found")
    } catch {
      guard case let .unreadableConfiguration(folder, _) = error else {
        Issue.record("expected an unreadable configuration, got \(error)")
        return
      }

      #expect(folder == directory.location(of: "services"))
      #expect(error.description.contains("services/use-cases.yml"))
    }
  }

  @Test
  func `naming the root directly accepts a root`() throws {
    let directory = try workspace()

    #expect(try finder().requireRoot(at: directory.url).directory == directory.url)
  }

  @Test
  func `naming a child scope directly is refused as a child scope`() throws {
    let directory = try workspace()
    let child = directory.location(of: "services/pay")

    do throws(RootFindingError) {
      _ = try finder().requireRoot(at: child)
      Issue.record("a child scope was accepted as the root")
    } catch {
      #expect(error == .notTheRoot(child))
      #expect(error.description.contains("child scope"))
      #expect(error.description.contains("root: true"))
    }
  }

  @Test
  func `naming a folder with no configuration is refused`() throws {
    let directory = try workspace()
    let folder = directory.location(of: "services")

    #expect(throws: RootFindingError.noConfiguration(folder)) {
      try finder().requireRoot(at: folder)
    }
  }

  @Test
  func `naming a folder never searches above it`() throws {
    let directory = try workspace()
    let folder = directory.location(of: "services/pay/src")

    #expect(throws: RootFindingError.noConfiguration(folder)) {
      try finder().requireRoot(at: folder)
    }
  }

  @Test
  func `a use-cases file that is a symlink on the way up is refused, not read`() throws {
    let directory = try workspace()
    try directory.write("template.yml", "root: true\n")
    try directory.symlink("services/use-cases.yml", to: "../template.yml")
    let start = directory.location(of: "services/pay")

    do throws(RootFindingError) {
      _ = try finder().findRoot(from: start)
      Issue.record("a root was found")
    } catch {
      #expect(error == .configurationIsSymlink(directory.location(of: "services")))
      #expect(error.description.contains("services/use-cases.yml"))
      #expect(error.description.contains("symlink"))
    }
  }

  @Test
  func `naming a folder whose use-cases file is a symlink is refused`() throws {
    let directory = try TemporaryDirectory()
    try directory.write("template.yml", "root: true\n")
    try directory.symlink("use-cases.yml", to: "template.yml")

    #expect(throws: RootFindingError.configurationIsSymlink(directory.url)) {
      try finder().requireRoot(at: directory.url)
    }
  }

  @Test
  func `a named pipe called use-cases dot yml is passed over and never opened`() throws {
    let directory = try workspace()
    try directory.makeFIFO("services/pay/src/use-cases.yml")

    let root = try finder().findRoot(from: directory.location(of: "services/pay/src"))

    #expect(root.directory == directory.url)
  }

  @Test(arguments: ["Use-Cases.yml", "USE-CASES.YML", "use-cases.YML", "use-cases.yaml"])
  func `a use-cases file spelt another way is not the root, even where the system finds it`(
    name: String,
  ) throws {
    let directory = try TemporaryDirectory()
    try directory.write(name, "root: true\n")
    let start = directory.url

    #expect(throws: RootFindingError.noRootFound(startingAt: start)) {
      try finder().findRoot(from: start)
    }
    #expect(throws: RootFindingError.noConfiguration(start)) {
      try finder().requireRoot(at: start)
    }
  }

  @Test
  func `a use-cases file spelt another way is passed over on the way up`() throws {
    let directory = try workspace()
    try directory.write("services/pay/src/Use-Cases.yml", "root: true\nuse_cases_dir: wrong\n")

    let root = try finder().findRoot(from: directory.location(of: "services/pay/src"))

    #expect(root.directory == directory.url)
    #expect(root.settings.useCasesDirectory.text == "use-cases")
  }
}
