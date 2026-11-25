/// The parts of the results store a `verify` step works with: the writer of its runs, the finder
/// of its open runs, the reader of its files and the lock of a run.
struct VerifyStore: Sendable {
  let writer: any VerifyRunWriting
  let finder: any OpenRunFinding
  let access: any StoreFileAccessing
  let locks: any RunLocking

  init(
    writer: any VerifyRunWriting,
    finder: any OpenRunFinding,
    access: any StoreFileAccessing,
    locks: any RunLocking,
  ) {
    self.writer = writer
    self.finder = finder
    self.access = access
    self.locks = locks
  }

  /// The store on the real file system, checked against the bundled schemas.
  ///
  /// - Parameter clock: The time of `created_at`, `finished_at` and the time part of a run id.
  init(clock: any Timekeeping = SystemTimekeeper()) throws(StoreSchemaLoadingError) {
    try self.init(
      writer: RunWriter(clock: clock),
      finder: OpenRunFinder(),
      access: StoreFileAccess(
        fileSystem: LocalFileSystem(),
        json: JSONReader(),
      ),
      locks: FlockRunLock(),
    )
  }
}

extension Result where Success == VerifyStore, Failure == StoreSchemaLoadingError {
  /// The store, or the refusal that its schemas could not be loaded.
  func opened() throws(VerifyError) -> VerifyStore {
    switch self {
    case let .success(store):
      return store
    case let .failure(error):
      throw .storage("the store's schemas could not be loaded: \(error)")
    }
  }
}
