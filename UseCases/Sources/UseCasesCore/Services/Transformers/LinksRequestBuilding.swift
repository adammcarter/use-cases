/// Writes the request of a links job (chapter 10 §11).
protocol LinksRequestBuilding: Sendable {
  /// The request document for one `links:` entry of the bridge settings.
  ///
  /// - Parameters:
  ///   - workspace: The loaded workspace the links are asked for.
  ///   - settings: The entry's `settings`, passed unchanged; `nil` when it has none.
  func request(
    for workspace: LoadedWorkspace,
    settings: AuthoredValue?,
  ) -> StoreJSONValue
}
