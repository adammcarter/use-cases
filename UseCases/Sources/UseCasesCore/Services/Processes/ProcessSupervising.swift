/// Runs one command to its end and brings back how it ended and what it printed: the process
/// supervisor of chapter 14, shared by `verify --run` and the transformers.
protocol ProcessSupervising: Sendable {
  /// Starts the command directly in its own process group, with no input, and watches it until
  /// it ends, its time runs out, or a cancellation arrives. In the last two cases the whole
  /// group is stopped before this returns. A command that ends badly is a `ProcessRun`; only a
  /// command that cannot be supervised at all throws.
  func run(_ request: ProcessRequest) async throws(ProcessSupervisingError) -> ProcessRun
}
