import Foundation

/// Asks git itself where the hooks are: the work tree, the hooks folder and `core.hooksPath`.
public struct GitInspector: GitInspecting {
  private static let timeout = Duration.seconds(30)

  private let supervisor: any ProcessSupervising
  private let fileSystem: any FileSystemReading

  /// Makes the inspector that runs the `git` on this machine's PATH.
  ///
  /// - Parameter cancellation: Says whether the request was cancelled, which stops git.
  public init(cancellation: any CancellationObserving) {
    self.init(
      supervisor: ProcessSupervisor(cancellation: cancellation),
      fileSystem: LocalFileSystem(),
    )
  }

  init(
    supervisor: any ProcessSupervising,
    fileSystem: any FileSystemReading,
  ) {
    self.supervisor = supervisor
    self.fileSystem = fileSystem
  }

  public func locate(from folder: URL) async throws(HooksError) -> GitLocation {
    let top = try await answer(
      ["rev-parse", "--show-toplevel"],
      in: folder,
    )

    guard top.exitCode == 0, let workTree = top.lastLine else {
      throw .notAGitRepository(folder: folder.path)
    }

    let hooks = try await answer(
      ["rev-parse", "--git-path", "hooks"],
      in: folder,
    )

    guard hooks.exitCode == 0, let path = hooks.lastLine else {
      throw .gitUnavailable(reason: "it could not say where this clone's hooks are")
    }

    let configured = try await answer(
      ["config", "--get", "core.hooksPath"],
      in: folder,
    )

    // Exit 1 is "not set"; any other failure is git not answering.
    guard configured.exitCode == 0 || configured.exitCode == 1 else {
      throw .gitUnavailable(reason: "it could not read core.hooksPath")
    }

    return GitLocation(
      workTree: canonicalLocation(of: URL(fileURLWithPath: workTree)),
      hooksFolder: canonicalLocation(
        of: path.hasPrefix("/")
          ? URL(fileURLWithPath: path)
          : folder.appendingPathComponent(path),
      ),
      isManaged: configured.exitCode == 0,
    )
  }

  /// Runs git in `folder`. A command that ends badly is its exit code; one that cannot be run, or
  /// did not end by itself, is git being unavailable.
  private func answer(
    _ arguments: [String],
    in folder: URL,
  ) async throws(HooksError) -> GitAnswer {
    let run: ProcessRun

    do {
      run = try await supervisor.run(
        ProcessRequest(
          arguments: ["git"] + arguments,
          workingDirectory: folder,
          reportPath: nil,
          timeout: Self.timeout,
        ),
      )
    } catch {
      throw .gitUnavailable(reason: Self.reason(of: error))
    }

    guard case let .exited(code) = run.termination else {
      throw .gitUnavailable(reason: "git did not finish answering")
    }

    return GitAnswer(
      exitCode: code,
      text: run.console.text,
    )
  }

  /// The real location with every symlink resolved. A hooks folder that is not there yet is
  /// resolved from the nearest folder that is, so it is spelled as its neighbours are.
  private func canonicalLocation(of location: URL) -> URL {
    var existing = location
    var missing: [String] = []

    while existing.path != "/", (try? fileSystem.kindOfItem(at: existing)) == nil {
      missing.insert(
        existing.lastPathComponent,
        at: 0,
      )
      existing = existing.deletingLastPathComponent()
    }

    return missing.reduce(fileSystem.canonicalLocation(of: existing)) { folder, name in
      folder.appendingPathComponent(name)
    }
  }

  private static func reason(of error: ProcessSupervisingError) -> String {
    switch error {
    case let .couldNotLaunch(reason), let .captureUnavailable(reason), let .waitFailed(reason):
      reason
    }
  }
}
