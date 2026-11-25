import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesCLI

/// A folder to set up with `init`, a place for the checks' copies of it to be made, and a
/// command line that runs from it.
struct InitFolder {
  /// A groups file that names a use case that is not there, which makes a workspace INVALID.
  static let unknownIdGroups = """
  schema_version: 1
  groups:
    g:
      include:
        ids: [nope.nothing]

  """

  let folder: TemporaryFolder
  let scratch: TemporaryFolder

  init() throws {
    folder = try TemporaryFolder()
    scratch = try TemporaryFolder()
  }

  var url: URL {
    folder.url
  }

  /// The folder as the system spells it with every symlink resolved, as `init` names it.
  var realPath: String {
    guard let resolved = realpath(url.path, nil) else {
      return url.path
    }

    defer {
      free(resolved)
    }

    return String(cString: resolved)
  }

  /// The hooks of this folder as a git clone would have them, without asking git: the folder is
  /// the top of the work tree, and its hooks are in `.git/hooks`.
  func clone(isManaged: Bool = false) -> HookPlanner {
    HookPlanner(
      git: MockGitInspector(
        location: GitLocation(
          workTree: URL(fileURLWithPath: realPath),
          hooksFolder: URL(fileURLWithPath: realPath).appendingPathComponent(".git/hooks"),
          isManaged: isManaged,
        ),
      ),
    )
  }

  /// Runs the command line from the folder, as a person at a terminal when `isTerminal`.
  /// `clock` is what the runner's cancellation watcher waits on between looks; left out, the
  /// runner's own default.
  func run(
    _ arguments: [String],
    from directory: URL? = nil,
    isTerminal: Bool = false,
    prompter: any Prompting = MockPrompter(),
    hooks: (any HookPlanning)? = nil,
    program: String = "/opt/use-cases/bin/use-cases",
    viewer: any PlanViewing = OverlayPlanViewer(),
    writer: any PlanWriting = AtomicPlanWriter(),
    cancellation: any CancellationScoping = ObservedCancellationScope(
      makeObserver: {
        MockCancellation.never
      },
    ),
    clock: (any Clock<Duration>)? = nil,
  ) async -> CommandResult {
    guard let clock else {
      return await CommandLineRunner(
        loader: WorkspaceLoader(),
        prompter: prompter,
        hooks: hooks,
        viewer: viewer,
        writer: writer,
        cancellation: cancellation,
        isTerminal: isTerminal,
        program: ProgramPath(installedAt: program),
        workingDirectory: directory ?? url,
      ).run(arguments: arguments)
    }

    return await CommandLineRunner(
      loader: WorkspaceLoader(),
      prompter: prompter,
      hooks: hooks,
      viewer: viewer,
      writer: writer,
      cancellation: cancellation,
      isTerminal: isTerminal,
      program: ProgramPath(installedAt: program),
      workingDirectory: directory ?? url,
      clock: clock,
    ).run(arguments: arguments)
  }

  /// The files below the folder with what they hold, folders not listed, for comparing a folder
  /// before and after a command.
  func snapshot() throws -> [String: String] {
    var found: [String: String] = [:]
    let prefix = url.path + "/"

    let walker = FileManager.default.enumerator(atPath: url.path)

    while let path = walker?.nextObject() as? String {
      let location = prefix + path
      var isFolder: ObjCBool = false

      if FileManager.default.fileExists(atPath: location, isDirectory: &isFolder),
         !isFolder.boolValue
      {
        found[path] = try String(contentsOfFile: location, encoding: .utf8)
      }
    }

    return found
  }

  func read(_ path: String) throws -> String {
    try String(
      contentsOf: url.appendingPathComponent(path),
      encoding: .utf8,
    )
  }
}
