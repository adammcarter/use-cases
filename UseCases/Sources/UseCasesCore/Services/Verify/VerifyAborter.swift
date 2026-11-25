import Foundation

/// Closes open runs: a started verify run nobody will finish, or a record run cut off mid-write.
public struct VerifyAborter: VerifyAborting {
  /// The note an aborted run keeps (chapter 12 §11).
  static let abortedNote = "aborted: closed by `use-cases verify --abort`"

  private let store: Result<VerifyStore, StoreSchemaLoadingError>

  /// An aborter over the real file system and the system clock.
  public init() {
    self.init(
      store: Result { () throws(StoreSchemaLoadingError) in
        try VerifyStore()
      },
    )
  }

  init(store: Result<VerifyStore, StoreSchemaLoadingError>) {
    self.store = store
  }

  public func abort(
    _ request: VerifyAbortRequest,
    in root: URL,
  ) async throws(VerifyError) -> AbortedVerifyRun {
    let store = try store.opened()
    let run = try chosen(
      by: request,
      in: root,
      store: store,
    )
    let folder = store.folder(
      of: run,
      in: root,
    )

    let outcome: Result<AbortedVerifyRun, VerifyError>?

    do {
      outcome = try await store.locks.holding(run: folder.url) {
        close(
          run,
          in: root,
          writer: store.writer,
        )
      }
    } catch {
      throw .storage(error.description)
    }

    guard let outcome else {
      throw .beingFinished(run.text)
    }

    return try outcome.get()
  }

  /// The run to close: the one named, or the only one open. A run named that is damaged is closed
  /// when it still can be; otherwise, and for a request that names none while one is damaged, the
  /// damaged file is named (chapter 13 §6).
  private func chosen(
    by request: VerifyAbortRequest,
    in root: URL,
    store: VerifyStore,
  ) throws(VerifyError) -> RunIdentifier {
    if let text = request.runIdentifier {
      return try Self.named(
        text,
        found: store.find(
          text,
          in: root,
        ),
      )
    }

    let open = try store.openIdentifiers(in: root)

    switch open.count {
    case 0:
      throw .noOpenRun
    case 1:
      return open[0]
    default:
      throw .severalOpenRuns(open.map(\.text))
    }
  }

  private static func named(
    _ text: String,
    found: FoundRun,
  ) throws(VerifyError) -> RunIdentifier {
    switch found {
    case let .open(run):
      return run.identifier
    case let .openRecord(identifier):
      return identifier
    case let .damaged(run):
      guard run.canBeClosed else {
        throw .storage(run.message)
      }

      return run.identifier
    case .sealed:
      throw .alreadySealed(text)
    case .missing:
      throw .noSuchRun(text)
    }
  }

  /// Seals the run as interrupted, with no results: its log is replaced by an empty one first,
  /// because lines an unfinished finish staged are never evidence, whole or torn. The manifest is
  /// finalized to say why. It runs with the run's lock held.
  private func close(
    _ run: RunIdentifier,
    in root: URL,
    writer: any VerifyRunWriting,
  ) -> Result<AbortedVerifyRun, VerifyError> {
    do {
      let open = try writer.reopenRun(
        run,
        in: root,
      )

      try writer.finalize(
        open.manifest.adding(note: Self.abortedNote),
        of: open,
      )
      try writer.clearResults(of: open)
      _ = try writer.seal(
        open,
        termination: .interrupted,
      )

      return .success(AbortedVerifyRun(runIdentifier: run.text))
    } catch {
      guard case .sealed = error else {
        return .failure(.storage(error.description))
      }

      return .failure(.alreadySealed(run.text))
    }
  }
}
