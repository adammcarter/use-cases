import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Resolving the roots is the first thing every command does, and the answer is
/// four paths plus a record of WHERE each one came from. The provenance block,
/// the refusal of an unknown component, and the defaults a workspace with no
/// `use-cases.yml` gets are all behaviour the TypeScript suite pins.
struct WorkspaceContextResolverTests {
  private let temporary: TemporaryDirectory
  private let registry: SchemaRegistry

  init() throws {
    temporary = try TemporaryDirectory()
    registry = try WorkspaceFixture.registry()
  }

  /// The temporary directory's REAL path.
  ///
  /// `TemporaryDirectory` resolves symlinks with `resolvingSymlinksInPath()`,
  /// which strips a leading `/private` — so on macOS it hands back `/var/...`
  /// while `realpath(3)`, which is what Node's `realpathSync` answers and what
  /// the resolver uses, answers `/private/var/...`. The tests compare against
  /// the latter.
  private var workspacePath: String {
    WorkspaceFixture.realPath(temporary.url.path)
  }

  private func resolve(
    _ options: ResolveWorkspaceContextOptions,
  ) throws -> ResolvedWorkspaceContext {
    try WorkspaceContextResolver.resolve(options: options, registry: registry)
  }

  private func resolveWorkspace() throws -> ResolvedWorkspaceContext {
    try resolve(ResolveWorkspaceContextOptions(workspaceRoot: workspacePath))
  }

  private func writeConfiguration(_ contents: String) throws {
    try temporary.writeFile("use-cases.yml", contents: contents)
  }

  // MARK: - A workspace with no config

  @Test
  func `a workspace with no config resolves to the defaults`() throws {
    let context = try resolveWorkspace()

    #expect(context.workspaceRoot == workspacePath)
    #expect(context.dataRoot == workspacePath)
    #expect(context.useCasesRoot == workspacePath + "/use-cases")
    #expect(context.componentIdentifier == "use-cases")
    #expect(context.configPath == nil)
  }

  @Test
  func `a workspace with no config carries no verifiers, gate or trust anchor`() throws {
    let context = try resolveWorkspace()

    #expect(context.verifiers == ResolvedWorkspaceVerifiers())
    #expect(context.releaseGate == nil)
    #expect(context.approvalTrust == nil)
    #expect(context.diagnostics.isEmpty)
  }

  @Test
  func `a workspace with no config says every root came from a default`() throws {
    let context = try resolveWorkspace()

    #expect(context.provenance.dataRoot == .default)
    #expect(context.provenance.useCasesRoot == .default)
    #expect(context.provenance.componentIdentifier == .default)
  }

  // MARK: - Where the workspace root came from

  @Test
  func `an explicit workspace root is recorded as explicit`() throws {
    let context = try resolveWorkspace()

    #expect(context.provenance.workspaceRoot == .explicit)
  }

  @Test
  func `no workspace root falls back to the working directory, and says so`() throws {
    let context = try resolve(ResolveWorkspaceContextOptions())

    #expect(context.provenance.workspaceRoot == .currentDirectory)
    #expect(
      context.workspaceRoot
        == WorkspaceFixture.realPath(FileManager.default.currentDirectoryPath),
    )
  }

  @Test
  func `a symlinked workspace root resolves to what it points at`() throws {
    let real = try temporary.makeDirectory("real")
    let link = try temporary.makeSymlink("link", to: real)

    let context = try resolve(ResolveWorkspaceContextOptions(workspaceRoot: link.path))

    #expect(context.workspaceRoot == WorkspaceFixture.realPath(real.path))
  }

  @Test
  func `a workspace root that does not exist is kept as written`() throws {
    let absent = workspacePath + "/absent"

    let context = try resolve(ResolveWorkspaceContextOptions(workspaceRoot: absent))

    #expect(context.workspaceRoot == absent)
    #expect(context.provenance.workspaceRoot == .explicit)
  }

  // MARK: - Where the data root came from

  @Test
  func `a config moves the data root and says the config decided it`() throws {
    _ = try temporary.makeDirectory("data")
    try writeConfiguration(WorkspaceFixture.configuration(dataRoot: "data"))

    let context = try resolveWorkspace()

    #expect(context.dataRoot == workspacePath + "/data")
    #expect(context.provenance.dataRoot == .workspaceConfig)
  }

  @Test
  func `an override beats the config and says the override decided it`() throws {
    _ = try temporary.makeDirectory("data")
    _ = try temporary.makeDirectory("elsewhere")
    try writeConfiguration(WorkspaceFixture.configuration(dataRoot: "data"))

    let context = try resolve(
      ResolveWorkspaceContextOptions(
        workspaceRoot: workspacePath,
        dataRootOverride: "elsewhere",
      ),
    )

    #expect(context.dataRoot == workspacePath + "/elsewhere")
    #expect(context.provenance.dataRoot == .override)
  }

  @Test
  func `an absolute override is taken as it stands`() throws {
    let elsewhere = try temporary.makeDirectory("elsewhere")

    let context = try resolve(
      ResolveWorkspaceContextOptions(
        workspaceRoot: workspacePath,
        dataRootOverride: elsewhere.path,
      ),
    )

    #expect(context.dataRoot == WorkspaceFixture.realPath(elsewhere.path))
    #expect(context.provenance.dataRoot == .override)
  }

  @Test
  func `an empty override resolves to the workspace root and claims no origin`() throws {
    let context = try resolve(
      ResolveWorkspaceContextOptions(workspaceRoot: workspacePath, dataRootOverride: ""),
    )

    #expect(context.dataRoot == workspacePath)
    #expect(context.provenance.dataRoot == .default)
  }

  @Test
  func `a symlinked data root resolves to what it points at`() throws {
    let real = try temporary.makeDirectory("real-data")
    try temporary.makeSymlink("data", to: real)
    try writeConfiguration(WorkspaceFixture.configuration(dataRoot: "data"))

    let context = try resolveWorkspace()

    #expect(context.dataRoot == WorkspaceFixture.realPath(real.path))
    #expect(context.useCasesRoot == WorkspaceFixture.realPath(real.path) + "/use-cases")
  }

  // MARK: - Where the use-cases root came from

  @Test
  func `a config moves the use-cases root and says the config decided it`() throws {
    try writeConfiguration(WorkspaceFixture.configuration(useCasesDirectory: "rows/here"))

    let context = try resolveWorkspace()

    #expect(context.useCasesRoot == workspacePath + "/rows/here")
    #expect(context.provenance.useCasesRoot == .workspaceConfig)
  }

  @Test
  func `the use-cases root hangs off the data root, not the workspace root`() throws {
    _ = try temporary.makeDirectory("data")
    try writeConfiguration(WorkspaceFixture.configuration(dataRoot: "data"))

    let context = try resolveWorkspace()

    #expect(context.useCasesRoot == workspacePath + "/data/use-cases")
  }

  // MARK: - The component

  @Test
  func `a component option is taken as given and says it was an option`() throws {
    let context = try resolve(
      ResolveWorkspaceContextOptions(workspaceRoot: workspacePath, component: "shop"),
    )

    #expect(context.componentIdentifier == "shop")
    #expect(context.provenance.componentIdentifier == .option)
  }

  @Test
  func `a declared component is used when no option is given`() throws {
    try writeConfiguration(WorkspaceFixture.configuration(componentIdentifier: "shop"))

    let context = try resolveWorkspace()

    #expect(context.componentIdentifier == "shop")
    #expect(context.provenance.componentIdentifier == .workspaceConfig)
  }

  @Test
  func `an option matching the declared component is accepted`() throws {
    try writeConfiguration(WorkspaceFixture.configuration(componentIdentifier: "shop"))

    let context = try resolve(
      ResolveWorkspaceContextOptions(workspaceRoot: workspacePath, component: "shop"),
    )

    #expect(context.componentIdentifier == "shop")
    #expect(context.provenance.componentIdentifier == .option)
  }

  @Test
  func `an option contradicting the declared component is refused`() throws {
    try writeConfiguration(WorkspaceFixture.configuration(componentIdentifier: "shop"))

    let error = #expect(throws: WorkspaceError.self) {
      try resolve(
        ResolveWorkspaceContextOptions(workspaceRoot: workspacePath, component: "warehouse"),
      )
    }

    #expect(error?.code == "component.unknown")
    #expect(
      error?.message == "Unknown component 'warehouse'. Declared component is 'shop'.",
    )
  }

  // MARK: - The config path

  @Test
  func `the config path is the workspace-relative file name when a config exists`() throws {
    try writeConfiguration(WorkspaceFixture.configuration())

    let context = try resolveWorkspace()

    #expect(context.configPath == "use-cases.yml")
  }

  @Test
  func `a config that validates cleanly reports no diagnostics`() throws {
    try writeConfiguration(WorkspaceFixture.configuration())

    let context = try resolveWorkspace()

    #expect(context.diagnostics.isEmpty)
  }

  // MARK: - Broken configs

  @Test
  func `a config that is not YAML is a parse error`() throws {
    try writeConfiguration("schema_version: [1, 2\n")

    let error = #expect(throws: WorkspaceError.self) {
      try resolveWorkspace()
    }

    #expect(error?.code == "workspace_config.parse_error")
    #expect(error?.message == "Unable to parse use-cases.yml.")
  }

  @Test(arguments: [
    "schema_version: 1\n",
    "- 1\n",
    "",
    "schema_version: 1\nworkspace_id: fixture\nunknown_key: 1\n",
  ])
  func `a config the schema refuses is a schema error`(contents: String) throws {
    try writeConfiguration(contents)

    let error = #expect(throws: WorkspaceError.self) {
      try resolveWorkspace()
    }

    #expect(error?.code == "workspace_config.schema_error")
    #expect(error?.message == "Invalid use-cases.yml.")
  }

  @Test(arguments: [
    #"a\..\b"#,
    #"..\b"#,
  ])
  func `a data root smuggling a parent segment past the schema is refused`(
    dataRoot: String,
  ) throws {
    try writeConfiguration(WorkspaceFixture.configuration(dataRoot: dataRoot))

    let error = #expect(throws: WorkspaceError.self) {
      try resolveWorkspace()
    }

    #expect(error?.code == "path.escape")
    #expect(error?.message == "Unsafe relative path '\(dataRoot)'.")
  }

  @Test
  func `a use cases dir smuggling a parent segment past the schema is refused`() throws {
    try writeConfiguration(
      WorkspaceFixture.configuration(useCasesDirectory: #"rows\..\..\out"#),
    )

    let error = #expect(throws: WorkspaceError.self) {
      try resolveWorkspace()
    }

    #expect(error?.code == "path.escape")
    #expect(error?.message == #"Unsafe relative path 'rows\..\..\out'."#)
  }

  @Test
  func `a keyring path smuggling a parent segment past the schema is refused`() throws {
    try writeConfiguration(
      WorkspaceFixture.configuration(
        extra: """
        approval_trust:
          keyring_path: keys\\..\\..\\out.json
        """,
      ),
    )

    let error = #expect(throws: WorkspaceError.self) {
      try resolveWorkspace()
    }

    #expect(error?.code == "path.escape")
  }

  // MARK: - The plugin root

  @Test
  func `an explicit plugin root is taken as given`() throws {
    let plugin = try temporary.makeDirectory("plugin")

    let context = try resolve(
      ResolveWorkspaceContextOptions(workspaceRoot: workspacePath, pluginRoot: plugin.path),
    )

    #expect(context.pluginRoot == WorkspaceFixture.realPath(plugin.path))
  }

  @Test
  func `a symlinked plugin root resolves to what it points at`() throws {
    let real = try temporary.makeDirectory("real-plugin")
    let link = try temporary.makeSymlink("plugin-link", to: real)

    let context = try resolve(
      ResolveWorkspaceContextOptions(workspaceRoot: workspacePath, pluginRoot: link.path),
    )

    #expect(context.pluginRoot == WorkspaceFixture.realPath(real.path))
  }

  // MARK: - The workspace-existence guard

  @Test
  func `an existing workspace root raises no diagnostic`() {
    let diagnostic = WorkspaceContextResolver
      .workspaceNotFoundDiagnostic(workspaceRoot: workspacePath)

    #expect(diagnostic == nil)
  }

  @Test
  func `an existing but empty workspace root is still legitimate`() throws {
    let empty = try temporary.makeDirectory("empty")

    let diagnostic = WorkspaceContextResolver
      .workspaceNotFoundDiagnostic(workspaceRoot: empty.path)

    #expect(diagnostic == nil)
  }

  @Test
  func `a workspace root that does not exist raises the canonical diagnostic`() throws {
    let absent = workspacePath + "/absent"

    let diagnostic = try #require(
      WorkspaceContextResolver.workspaceNotFoundDiagnostic(workspaceRoot: absent),
    )

    #expect(diagnostic.code == "workspace.not_found")
    #expect(diagnostic.code == WorkspaceContextResolver.workspaceNotFoundCode)
    #expect(diagnostic.severity == .error)
    #expect(diagnostic.message == "repo path does not exist: \(absent)")
    #expect(diagnostic.sourcePath == nil)
  }
}
