import UseCasesCore

/// A workspace that loaded and whose links resolved without a problem: what every command that
/// reads links starts from.
struct LinkedWorkspace {
  let workspace: LoadedWorkspace
  let resolution: LinkResolution
}
