import UseCasesCore
import UseCasesTestSupport

/// A links provider whose work goes on only once the test opens a gate: a command that reads,
/// caught in the middle of loading. The wait holds no thread. Once the gate is open it answers as
/// `links` does.
struct GatedTransformerLinks: TransformerLinkProviding {
  let gate: UseCasesTestSupport.Gate
  let links: any TransformerLinkProviding

  func links(for workspace: LoadedWorkspace) async throws(TransformerLinkingError)
    -> TransformedLinks
  {
    await gate.wait()

    return try await links.links(for: workspace)
  }
}
