@testable import UseCasesTransformers

func located(
  _ test: String,
  _ file: String?,
  _ line: Int?,
  _ status: ResultStatus,
) -> LocatedTest {
  LocatedTest(
    test: test,
    file: file,
    line: line,
    status: status,
  )
}
