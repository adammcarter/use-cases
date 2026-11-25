import Testing
@testable import UseCasesTransformers

struct TransformerFailureTests {
  @Test(arguments: [
    TransformerFailure.missingArguments,
    .unknownTransformer("nope"),
    .unsupportedJob(
      transformer: "junit",
      job: "links",
    ),
  ])
  func `wrong use of the program is a usage error`(failure: TransformerFailure) {
    #expect(failure.isUsageError)
  }

  @Test(arguments: [
    TransformerFailure.requestUnreadable(
      path: "p",
      reason: "r",
    ),
    .requestMalformed(reason: "r"),
    .unsupportedContract(2),
    .settingMissing("file"),
    .settingInvalid(
      name: "n",
      expected: "e",
    ),
    .reportUnreadable(
      path: "p",
      reason: "r",
    ),
    .reportMalformed(
      path: "p",
      reason: "r",
    ),
    .responseUnwritable(
      path: "p",
      reason: "r",
    ),
  ])
  func `a problem with the work is not a usage error`(failure: TransformerFailure) {
    #expect(!failure.isUsageError)
  }

  @Test
  func `an unknown transformer names the bundled ones`() {
    let text = TransformerFailure.unknownTransformer("nope").description

    #expect(text.contains("'nope'"))

    for name in TransformerCatalogue.names {
      #expect(text.contains(name))
    }
  }

  @Test
  func `messages say what to fix`() {
    #expect(TransformerFailure.settingMissing("file").description == "settings.file is required")
    #expect(
      TransformerFailure.unsupportedContract(nil).description
        == "unsupported contract (none): this program speaks contract 1",
    )
    #expect(
      TransformerFailure.unsupportedJob(
        transformer: "junit",
        job: "links",
      ).description
        == "junit does not do the links job",
    )
  }
}
