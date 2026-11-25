import Foundation

/// A workspace that loaded (chapter 09 §26): every scope, and every use case under its full id.
public struct LoadedWorkspace: Equatable, Sendable {
  /// The canonical folder of the workspace root.
  let root: URL

  /// The root scope first, then the others sorted by folder.
  let scopes: [LoadedScope]

  /// Scope by scope in that order, files by path, use cases as written.
  let useCases: [LoadedUseCase]

  /// Everything that is worth saying and does not make the workspace INVALID.
  let warnings: [Diagnostic]

  /// The root `use-cases-bridge.yml` when there is one and it is valid (chapter 09 §21).
  let bridge: BridgeSettings?

  /// The groups of the root `use-case-groups.yml`, in the order written, resolved against the
  /// use cases above (chapter 09 §22). Empty when there is no such file.
  let groups: [UseCaseGroup]

  /// The warnings of the optional root files, the bridge settings and the groups: valid, but
  /// worth saying (chapter 10 §18, chapter 03). Kept apart from ``warnings`` because only
  /// `validate` and `status` say them.
  let rootFileWarnings: [Diagnostic]

  /// Problems that make the workspace INVALID and wait for the stage that resolves links, to be
  /// raised with the marker and binding problems found there (chapter 09 §27, §34). Empty for
  /// a workspace that is not INVALID. Whoever asks for the links must refuse a workspace that
  /// holds any, which is why ``hasHeldProblems`` is public.
  let heldProblems: [Diagnostic]

  /// Whether the workspace is INVALID for a problem that waits for the links to be raised.
  public var hasHeldProblems: Bool {
    !heldProblems.isEmpty
  }
}
