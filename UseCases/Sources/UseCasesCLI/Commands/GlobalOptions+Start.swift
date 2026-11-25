import Foundation
import UseCasesCore

extension GlobalOptions {
  /// Where to look for the workspace: the folder `--workspace` names, or the current one.
  func start(from workingDirectory: URL) -> WorkspaceStart {
    guard workspace != nil else {
      return .searchingUpward(from: workingDirectory)
    }

    return .workspace(folder(from: workingDirectory))
  }

  /// The folder the command is about: the one `--workspace` names, or the current one. A command
  /// that never looks above it, `init`, starts here.
  func folder(from workingDirectory: URL) -> URL {
    guard let workspace else {
      return workingDirectory
    }

    // A relative path is read from where the command runs. It is joined by hand: resolving it
    // against a base URL that is not marked as a folder would drop the base's last name.
    let location =
      workspace.hasPrefix("/")
        ? URL(fileURLWithPath: workspace)
        : workingDirectory.appendingPathComponent(workspace)

    return location.standardizedFileURL
  }
}
