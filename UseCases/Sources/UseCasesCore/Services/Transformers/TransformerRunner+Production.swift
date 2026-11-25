extension TransformerRunner {
  /// A runner as production builds it: bundled transformers beside the running `use-cases`, a
  /// process supervisor that stops a transformer when the observer says the run was cancelled,
  /// and 120 seconds for each transformer to answer (chapter 10 §10).
  static func production(cancellation: any CancellationObserving) -> TransformerRunner {
    TransformerRunner(
      locator: TransformerLocator(
        executable: RunningExecutableLocator(),
        fileSystem: LocalFileSystem(),
      ),
      scratchMaker: TransformerScratchMaker(),
      supervisor: ProcessSupervisor(cancellation: cancellation),
      jsonReader: JSONReader(),
      jsonWriter: StoreJSONWriter(),
    )
  }
}
