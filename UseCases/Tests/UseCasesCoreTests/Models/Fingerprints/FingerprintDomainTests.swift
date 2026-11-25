import Testing
@testable import UseCasesCore

struct FingerprintDomainTests {
  @Test(
    arguments: [
      (FingerprintDomain.content, "use-cases/content/v1"),
      (FingerprintDomain.route, "use-cases/route/v1"),
      (FingerprintDomain.workspace, "use-cases/workspace/v1"),
      (FingerprintDomain.promise, "use-cases/promise/v1"),
    ],
  )
  func `each kind has the domain the chapter fixes`(
    row: (domain: FingerprintDomain, name: String),
  ) {
    #expect(row.domain.name == row.name)
  }

  @Test(
    arguments: [
      (FingerprintDomain.content, "uc-content-v1-sha256:"),
      (FingerprintDomain.route, "uc-route-v1-sha256:"),
      (FingerprintDomain.workspace, "uc-workspace-v1-sha256:"),
    ],
  )
  func `each shown kind has the external prefix the chapter fixes`(
    row: (domain: FingerprintDomain, prefix: String),
  ) {
    #expect(row.domain.externalPrefix == row.prefix)
  }

  @Test
  func `a promise fingerprint is the bare digest`() {
    #expect(FingerprintDomain.promise.externalPrefix == nil)
  }

  @Test
  func `the content reference is shown with the content prefix`() {
    let reference = ContentReference(
      byteLength: 3,
      digest: "efb223658e20ee620f5c7f42edb1f1146cda800481df6206f80e86ac400dd989",
    )

    #expect(
      reference.fingerprint
        == "uc-content-v1-sha256:efb223658e20ee620f5c7f42edb1f1146cda800481df6206f80e86ac400dd989",
    )
  }
}
