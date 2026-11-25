/// Notes what the files a plan replaces or deletes hold, for the plans whose planner did not, so
/// that the writer can tell a file someone changed since.
public protocol PlanRecording: Sendable {
  /// The same plans where every change to a file that is there knows what the file holds now. A
  /// change that already knows keeps what it knows, and a file that cannot be read is left for
  /// the writer to refuse.
  func recording(_ writes: [FolderWrite]) -> [FolderWrite]
}
