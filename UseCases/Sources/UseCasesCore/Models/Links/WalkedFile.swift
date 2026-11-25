/// One file the code walk reached: a file the scan reads.
struct WalkedFile: Equatable, Sendable {
  let path: WorkspacePath
  let kind: WalkedFileKind
}
