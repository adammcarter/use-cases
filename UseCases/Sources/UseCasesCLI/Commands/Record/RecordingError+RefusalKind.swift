import UseCasesCore

extension RecordingError {
  /// How a refusal to record is told to a script (chapter 16 §5).
  var refusalKind: RefusalKind {
    switch self {
    case .unknownStatus, .noUseCase, .ambiguousUseCase, .noRoute, .ambiguousRoute,
         .attachmentMissing, .attachmentIsFolder, .attachmentNotRegular, .attachmentUnreadable,
         .duplicateAttachmentName:
      .usage
    case .draft, .noFingerprint, .noReadyUseCase:
      .refused
    case .invalidWorkspace:
      .invalid
    case .storage:
      .storage
    }
  }
}
