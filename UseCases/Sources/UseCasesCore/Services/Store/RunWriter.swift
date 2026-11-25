import Foundation

/// Writes runs: allocation under a lock, publication through a temporary folder and a rename,
/// appends under the run, and sealing through a marker that cannot overwrite (chapter 12).
struct RunWriter: VerifyRunWriting {
  /// The lock file in `.use-cases/`. It is not in `runs/`, where any stray entry is a storage
  /// error (chapter 12 §22).
  static let lockFile = "allocation.lock"

  let files: any StoreFileWriting
  let locks: any StoreLocking
  let printer: any StoreJSONWriting
  let json: any JSONReading
  let allocator: any RunIdentifierAllocating
  let clock: any Timekeeping
  let access: any StoreFileAccessing
  let orderReader: any RunOrderReading
  let hasher: any Hashing
  let checks: StoreWriteChecks
  let runLocks: any RunLocking

  init(
    files: any StoreFileWriting,
    locks: any StoreLocking,
    printer: any StoreJSONWriting,
    json: any JSONReading,
    allocator: any RunIdentifierAllocating,
    clock: any Timekeeping,
    access: any StoreFileAccessing,
    orderReader: any RunOrderReading,
    hasher: any Hashing,
    checks: StoreWriteChecks,
    runLocks: any RunLocking = FlockRunLock(),
  ) {
    self.files = files
    self.locks = locks
    self.printer = printer
    self.json = json
    self.allocator = allocator
    self.clock = clock
    self.access = access
    self.orderReader = orderReader
    self.hasher = hasher
    self.checks = checks
    self.runLocks = runLocks
  }

  /// A writer over the real file system, checking every file against the bundled schemas.
  ///
  /// - Parameters:
  ///   - clock: The time of `created_at`, `finished_at` and the time part of a run id.
  ///   - random: The random part of a run id.
  ///   - files: How the store's files are written.
  ///   - runLocks: How the lock of a run is taken.
  init(
    clock: any Timekeeping = SystemTimekeeper(),
    random: any RandomBitsProviding = SystemRandomBits(),
    files: any StoreFileWriting = LocalStoreFileWriter(),
    loader: any StoreSchemaLoading = BundledStoreSchemaLoader(),
    runLocks: any RunLocking = FlockRunLock(),
  ) throws(StoreSchemaLoadingError) {
    let json = JSONReader()
    let access = StoreFileAccess(
      fileSystem: LocalFileSystem(),
      json: json,
    )

    try self.init(
      files: files,
      locks: FlockStoreLock(),
      printer: StoreJSONWriter(),
      json: json,
      allocator: RunIdentifierAllocator(
        clock: clock,
        random: random,
      ),
      clock: clock,
      access: access,
      orderReader: RunOrderReader(
        access: access,
        checker: loader.loadChecker(
          for: .runOrder,
          unknownMembers: .ignore,
        ),
      ),
      hasher: SHA256Hasher(),
      checks: StoreWriteChecks(loader: loader),
      runLocks: runLocks,
    )
  }

  /// Runs a read of the store, and says what went wrong with it as a writing error.
  func reading<Value>(_ read: () throws(StoreProblem) -> Value) throws(StoreWritingError) -> Value {
    do {
      return try read()
    } catch {
      throw .damaged(error)
    }
  }

  /// Where a run's folder is, once it is published.
  func folder(
    of run: RunIdentifier,
    in workspace: URL,
  ) -> StoreFile {
    StoreFile(workspace: workspace)
      .appending(StoreLayout.runsFolder)
      .appending(run.text)
  }
}
