import Testing
import UseCasesCore
@testable import UseCasesCLI

struct RecordingErrorRefusalKindTests {
  @Test(arguments: [
    (RecordingError.unknownStatus("x"), RefusalKind.usage),
    (RecordingError.noUseCase("x"), RefusalKind.usage),
    (RecordingError.ambiguousUseCase("x", matching: ["x.a", "x.b"]), RefusalKind.usage),
    (RecordingError.noRoute(useCase: "x", route: "y"), RefusalKind.usage),
    (
      RecordingError.ambiguousRoute(useCase: "x", route: "y", matching: ["ya", "yb"]),
      RefusalKind.usage,
    ),
    (RecordingError.attachmentMissing("/a.png"), RefusalKind.usage),
    (RecordingError.attachmentIsFolder("/a"), RefusalKind.usage),
    (RecordingError.attachmentNotRegular("/a"), RefusalKind.usage),
    (RecordingError.attachmentUnreadable(path: "/a", reason: "denied"), RefusalKind.usage),
    (RecordingError.duplicateAttachmentName("a.png"), RefusalKind.usage),
    (RecordingError.noReadyUseCase, RefusalKind.refused),
    (RecordingError.draft(useCase: "x", missing: ["intent"]), RefusalKind.refused),
    (RecordingError.noFingerprint(useCase: "x", route: "y"), RefusalKind.refused),
    (RecordingError.invalidWorkspace(problems: ["a: b"]), RefusalKind.invalid),
    (RecordingError.storage("disk full"), RefusalKind.storage),
  ])
  func `each way of not recording is told to a script with its kind`(
    error: RecordingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
