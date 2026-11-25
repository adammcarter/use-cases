import UseCasesCore

/// The services of the steps of `verify`.
struct Verifier {
  let starter: any VerifyStarting
  let finisher: any VerifyFinishing
  let runner: any VerifyRunning
  let aborter: any VerifyAborting
  let locator: any WorkspaceRootLocating

  init(
    starter: any VerifyStarting = VerifyStarter(),
    finisher: any VerifyFinishing = VerifyFinisher(),
    runner: any VerifyRunning = VerifyRunner(),
    aborter: any VerifyAborting = VerifyAborter(),
    locator: any WorkspaceRootLocating = WorkspaceLoader(),
  ) {
    self.starter = starter
    self.finisher = finisher
    self.runner = runner
    self.aborter = aborter
    self.locator = locator
  }
}
