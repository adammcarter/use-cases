import Foundation

extension VerifyFinisher {
  /// The run to finish: the one named, or the only one `--start` left open (chapter 13 §6 step
  /// 1). `nil` when there is none and there are no validations to have started one.
  func chosen(
    by request: VerifyFinishRequest,
    in workspace: LoadedWorkspace,
    store: VerifyStore,
  ) async throws(VerifyError) -> OpenVerifyRun? {
    if let text = request.runIdentifier {
      return try await named(
        text,
        in: workspace,
        store: store,
      )
    }

    let started = try store.openRuns(in: workspace.root).filter { $0.stamp.openedBy == .start }

    switch started.count {
    case 0:
      guard workspace.bridge?.validations.isEmpty ?? true else {
        throw .noStartedRun
      }

      return nil
    case 1:
      return started[0]
    default:
      throw .severalStartedRuns(started.map(\.identifier.text))
    }
  }

  private static func doNothing() async {}

  /// A run named with `--run-id`. A run `verify --run` opened is never finished here: it is
  /// either still running, which its lock says, or it stopped and can only be aborted.
  private func named(
    _ text: String,
    in workspace: LoadedWorkspace,
    store: VerifyStore,
  ) async throws(VerifyError) -> OpenVerifyRun {
    switch try store.find(text, in: workspace.root) {
    case .missing, .openRecord:
      throw .noSuchRun(text)
    case .sealed:
      throw .alreadySealed(text)
    case let .damaged(run):
      throw .storage(run.message)
    case let .open(run) where run.stamp.openedBy == .start:
      return run
    case let .open(run):
      let folder = store.folder(
        of: run.identifier,
        in: workspace.root,
      )
      let isFree: Void?

      do {
        isFree = try await store.locks.holding(
          run: folder.url,
          perform: Self.doNothing,
        )
      } catch {
        throw .storage(error.description)
      }

      throw isFree == nil
        ? .beingFinished(text)
        : .stoppedBeforeFinishing(text)
    }
  }
}
