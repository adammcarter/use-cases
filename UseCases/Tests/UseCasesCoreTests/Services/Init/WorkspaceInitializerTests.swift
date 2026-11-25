import Foundation
import Testing
@testable import UseCasesCore

struct WorkspaceInitializerTests {
  private static let everything = [
    "use-cases.yml", "use-cases/example.yml", "use-case-groups.yml", "use-cases-bridge.yml",
  ]

  private let directory: TemporaryDirectory
  private let initializer = WorkspaceInitializer()

  init() throws {
    directory = try TemporaryDirectory()
  }

  private func plan(
    _ form: InitForm = .full,
    prefix: String? = nil,
    in folder: URL? = nil,
  ) throws(InitError) -> InitPlan {
    try initializer.plan(
      InitRequest(
        folder: folder ?? directory.url,
        form: form,
        prefix: prefix,
      ),
    )
  }

  private func refusal(
    _ form: InitForm = .full,
    prefix: String? = nil,
    in folder: URL? = nil,
  ) -> InitError? {
    do {
      _ = try plan(
        form,
        prefix: prefix,
        in: folder,
      )
    } catch {
      return error
    }

    return nil
  }

  // MARK: - A folder with nothing in it

  @Test
  func `an empty folder gets the four files in the order of the chapter`() throws {
    let plan = try plan()

    #expect(plan.root == directory.url)
    #expect(plan.created == Self.everything)
    #expect(plan.kept.isEmpty)
    #expect(plan.writes.changes.map(\.path) == Self.everything)
    #expect(plan.writes.changes.allSatisfy { $0.action == .create })
  }

  @Test
  func `minimal is the workspace file alone`() throws {
    let plan = try plan(.minimal)

    #expect(plan.created == ["use-cases.yml"])
    #expect(plan.writes.changes.map(\.path) == ["use-cases.yml"])
  }

  @Test
  func `the prefix goes into the workspace file and into the group that selects the example`()
    throws
  {
    let plan = try plan(prefix: "shop")
    let texts = plan.writes.changes.map(\.text)

    #expect(
      texts[0]
        == "schema_version: 1\nroot: true\nprefix: shop\n\n"
        + "# discovery:        # optional: folders never searched for use cases or markers,\n"
        + "#   exclude:        # such as build output, or test data that holds marker "
        + "text as data.\n"
        + "#     - \"build/**\"\n"
        + "#     - \"tests/fixtures/**\"\n",
    )
    #expect(texts[2].contains("- shop.example\n"))
  }

  @Test
  func `the gitignore line is written last, after the files, when git is there`() throws {
    try directory.makeDirectory(".git")

    let plan = try plan()

    #expect(plan.gitignore == .added)
    #expect(plan.created == Self.everything)
    #expect(plan.writes.changes.map(\.path) == Self.everything + [".gitignore"])
  }

  @Test
  func `no version control is a note and no write`() throws {
    let plan = try plan()

    #expect(plan.gitignore == .skipped)
    #expect(plan.notes.count == 1)
  }

  // MARK: - Files that are there

  @Test
  func `a file that is there is kept, whatever it holds, and the others are made`() throws {
    try directory.write("use-case-groups.yml", "mine: true\n")

    let plan = try plan()

    #expect(plan.kept == ["use-case-groups.yml"])
    #expect(plan.created == ["use-cases.yml", "use-cases/example.yml", "use-cases-bridge.yml"])
  }

  @Test
  func `a workspace that init made is kept whole on a second run`() throws {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))
    try directory.write("use-cases/example.yml", InitTemplates.example)
    try directory.write("use-case-groups.yml", InitTemplates.groups(prefix: nil))
    try directory.write("use-cases-bridge.yml", InitTemplates.bridge)

    let plan = try plan()

    #expect(plan.created.isEmpty)
    #expect(plan.kept == Self.everything)
    #expect(plan.writes.isEmpty)
  }

  @Test
  func `an existing workspace gains the bridge template and never the example or the groups`()
    throws
  {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))

    let plan = try plan()

    #expect(plan.created == ["use-cases-bridge.yml"])
    #expect(plan.kept == ["use-cases.yml"])
  }

  @Test
  func `an existing workspace with minimal gains nothing`() throws {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))

    let plan = try plan(.minimal)

    #expect(plan.created.isEmpty)
    #expect(plan.kept == ["use-cases.yml"])
  }

  @Test(arguments: [nil, "shop"])
  func `the same prefix as the workspace's is no refusal`(prefix: String?) throws {
    try directory.write(
      "use-cases.yml",
      "schema_version: 1\nroot: true\n" + (prefix.map { text in "prefix: \(text)\n" } ?? ""),
    )

    #expect(throws: Never.self) {
      _ = try plan(prefix: prefix)
    }
  }

  @Test
  func `a different prefix is refused, and so is one for a workspace that has none`() throws {
    try directory.write("use-cases.yml", "schema_version: 1\nroot: true\nprefix: shop\n")
    let named = refusal(prefix: "other")
    try directory.write("use-cases.yml", "schema_version: 1\nroot: true\n")
    let unnamed = refusal(prefix: "shop")

    #expect(named == .differentPrefix(existing: "shop", asked: "other"))
    #expect(unnamed == .differentPrefix(existing: nil, asked: "shop"))
    #expect(unnamed?.message.contains("has no prefix") == true)
  }

  @Test
  func `a folder where a file would go is refused`() throws {
    try directory.makeDirectory("use-case-groups.yml")

    #expect(refusal() == .obstructed(
      path: "use-case-groups.yml",
      reason: "it is a folder, not a file",
    ))
  }

  @Test
  func `a symlink where a file would go is refused`() throws {
    try directory.write("elsewhere.yml", "x")
    try directory.symlink("use-cases-bridge.yml", to: "elsewhere.yml")

    #expect(refusal() == .obstructed(
      path: "use-cases-bridge.yml",
      reason: "it is a symlink, not a file",
    ))
  }

  // MARK: - Refusals

  @Test(arguments: ["Shop", "shop_", "shop..app", "-shop", "", "shop-", "a.b.", "sh op"])
  func `a prefix off the grammar is refused as not a valid prefix`(prefix: String) {
    let error = refusal(prefix: prefix)

    guard case let .invalidPrefix(text, _)? = error else {
      Issue.record("unexpected: \(String(describing: error))")
      return
    }

    #expect(text == prefix)
    #expect(error?.message.contains("not a valid prefix") == true)
  }

  @Test
  func `a bad prefix is refused before the folder is looked at`() {
    let missing = directory.location(of: "nowhere")

    #expect(refusal(prefix: "Bad", in: missing) != .notAFolder(path: missing.path))
  }

  @Test
  func `a child scope's use-cases file is not a workspace root`() throws {
    try directory.write("use-cases.yml", "schema_version: 1\nprefix: svc\n")

    let error = refusal()

    #expect(error == .notWorkspaceRoot(path: directory.url.path))
    #expect(error?.message.contains("not a workspace root") == true)
  }

  @Test
  func `a folder below a workspace root is inside it, and the message names the root`() throws {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))
    try directory.makeDirectory("services/pay")
    let below = directory.location(of: "services/pay")

    let error = refusal(in: below)

    #expect(error == .insideWorkspace(folder: below.path, root: directory.url.path))
    #expect(error?.message.contains("inside the workspace") == true)
  }

  @Test
  func `a folder below a child scope of a workspace is inside the workspace`() throws {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))
    try directory.write("svc/use-cases.yml", "schema_version: 1\nprefix: svc\n")
    try directory.makeDirectory("svc/src")

    let error = refusal(in: directory.location(of: "svc/src"))

    guard case .insideWorkspace? = error else {
      Issue.record("unexpected: \(String(describing: error))")
      return
    }
  }

  @Test
  func `a nested workspace's root is a workspace of its own and is not inside the outer one`()
    throws
  {
    try directory.write("use-cases.yml", InitTemplates.workspace(prefix: nil))
    try directory.write("vendor/use-cases.yml", InitTemplates.workspace(prefix: nil))

    let plan = try plan(in: directory.location(of: "vendor"))

    #expect(plan.kept == ["use-cases.yml"])
  }

  @Test
  func `a folder that is not there, or is a file, is not a folder`() throws {
    try directory.write("file", "x")

    for place in ["nowhere", "file"] {
      let location = directory.location(of: place)

      #expect(refusal(in: location) == .notAFolder(path: location.path))
    }
  }

  @Test
  func `a root file that cannot be read is an INVALID workspace`() throws {
    try directory.write("use-cases.yml", "schema_version: [\n")

    guard case let .invalidWorkspace(problems)? = refusal() else {
      Issue.record("not refused as invalid")
      return
    }

    #expect(problems.count == 1)
    #expect(problems.first?.contains("use-cases.yml") == true)
  }

  @Test
  func `a root file that is a symlink is an INVALID workspace`() throws {
    try directory.write("real.yml", InitTemplates.workspace(prefix: nil))
    try directory.symlink("use-cases.yml", to: "real.yml")

    guard case .invalidWorkspace? = refusal() else {
      Issue.record("not refused as invalid")
      return
    }
  }

  @Test
  func `nothing is written by planning`() throws {
    try directory.makeDirectory(".git")

    _ = try plan()

    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.url.path) == [".git"])
  }

  @Test
  func `a folder with nothing in it is not an existing workspace`() throws {
    #expect(try !plan().isExistingWorkspace)
  }

  @Test
  func `a folder that is already the root is an existing workspace, whichever form is asked`()
    throws
  {
    try directory.write("use-cases.yml", "schema_version: 1\nroot: true\n")

    #expect(try plan().isExistingWorkspace)
    #expect(try plan(.minimal).isExistingWorkspace)
  }
}
