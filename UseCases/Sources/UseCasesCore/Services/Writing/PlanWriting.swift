import Foundation

/// Applies plans of file changes, all or nothing: every file is staged beside its target first,
/// then each is swapped in by a rename, and a failure part way undoes what was done
/// (`docs/architecture.md` §2).
public protocol PlanWriting: Sendable {
  /// Makes every change of every plan, in order, each under its own folder. Every refusal that can
  /// be known beforehand is found before the first byte is written: a file to create that is
  /// already there, a file to replace or delete that is not, a file standing where a folder is
  /// needed. A failure after that undoes every change already made, so no file is left half
  /// changed.
  ///
  /// Only one writer at a time makes changes in a workspace: it holds a lock on a file in the
  /// workspace's `.use-cases/` folder, made if it is absent, from before it looks at the files
  /// until it is through. A file to replace or delete that no longer holds what it held when it
  /// was planned (``FileChange/expected``) is refused, and nothing is written.
  ///
  /// - Parameters:
  ///   - writes: What to write, each plan under the folder its paths are relative to.
  ///   - workspace: The workspace root, whose `.use-cases/` folder holds the lock.
  /// - Throws: ``PlanWritingError``.
  func apply(
    _ writes: [FolderWrite],
    lockingIn workspace: URL,
  ) throws(PlanWritingError)
}

extension PlanWriting {
  /// Makes the changes of one plan under `root`.
  func apply(
    _ plan: WritePlan,
    in root: URL,
  ) throws(PlanWritingError) {
    try apply(
      [
        FolderWrite(
          folder: root,
          plan: plan,
        ),
      ],
      lockingIn: root,
    )
  }
}
