/// Reads the use case or id prefix a command line names (chapter 16 §9 and §13).
public protocol UseCaseTargeting: Sendable {
  /// The full ids of the use cases `target` names in `workspace`.
  ///
  /// An exact use case id always wins over a prefix: it names that use case alone, even when
  /// other ids start with it. Otherwise the target is an id prefix, and it names every use case
  /// under it, by whole dotted segments: `shop.cart` names `shop.cart.add`, never `shop.cartx`.
  ///
  /// - Parameters:
  ///   - target: The text the person typed.
  ///   - workspace: A workspace that loaded.
  /// - Returns: The ids it names, never empty.
  /// - Throws: ``UseCaseTargetingError`` when it names no use case and no id prefix.
  func identifiers(
    matching target: String,
    in workspace: LoadedWorkspace,
  ) throws(UseCaseTargetingError) -> Set<String>
}
