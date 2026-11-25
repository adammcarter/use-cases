import Foundation

/// Reads `.use-cases/run-order.json` (chapter 12 §9).
struct RunOrderReader: RunOrderReading {
  private let access: any StoreFileAccessing
  private let checker: any SchemaChecking

  init(
    access: any StoreFileAccessing,
    checker: any SchemaChecking,
  ) {
    self.access = access
    self.checker = checker
  }

  /// A reader over the real file system, checking against the bundled schema.
  init(
    fileSystem: any FileSystemReading = LocalFileSystem(),
    json: any JSONReading = JSONReader(),
    loader: any StoreSchemaLoading = BundledStoreSchemaLoader(),
  ) throws(StoreSchemaLoadingError) {
    try self.init(
      access: StoreFileAccess(
        fileSystem: fileSystem,
        json: json,
      ),
      checker: loader.loadChecker(
        for: .runOrder,
        unknownMembers: .ignore,
      ),
    )
  }

  func readRunOrder(in workspace: URL) throws(StoreProblem) -> RunOrder? {
    let file = StoreFile(workspace: workspace).appending(StoreLayout.runOrderFile)

    guard try access.kind(of: file) != nil else {
      return nil
    }

    let value = try access.document(
      access.requiredBytes(of: file),
      in: file,
    )

    guard case let .object(members) = value else {
      throw .corrupt(file.location, "it is not a JSON object")
    }
    if case let .integer(version)? = members.first(where: { $0.key == "order_version" })?.value,
       version > 1
    {
      throw .unsupported(file.location, "order_version \(version) is newer than this core reads")
    }

    let failures = checker.check(value)
    guard failures.isEmpty else {
      throw .corrupt(file.location, failures.prefix(3).map(\.description).joined(separator: "; "))
    }

    do {
      return try RunOrder(lastRunIdentifier: AuthoredObject(value, at: "").requiredRunIdentifier(
        "last_run_id",
      ))
    } catch {
      throw .corrupt(file.location, error.description)
    }
  }
}
