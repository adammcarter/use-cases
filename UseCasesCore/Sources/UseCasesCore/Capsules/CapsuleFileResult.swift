/// One entry met under `demo-capsules/` (`CapsuleFileResult`).
public struct CapsuleFileResult: Sendable, Equatable {
  /// Relative to the data root, with `/` separators.
  public let path: String
  public let status: CapsuleFileStatus
  /// The semantic hash of the file's text; nil for an entry that was never
  /// read.
  public let fileHash: String?

  public init(
    path: String,
    status: CapsuleFileStatus,
    fileHash: String? = nil,
  ) {
    self.path = path
    self.status = status
    self.fileHash = fileHash
  }

  /// `{ path, status, file_hash? }`.
  public var jsonValue: JSONValue {
    var object = JSONObject([
      ("path", .string(path)),
      ("status", .string(status.rawValue)),
    ])
    object["file_hash"] = fileHash.map(JSONValue.string)
    return .object(object)
  }

  /// The same entry with another status.
  func with(status: CapsuleFileStatus) -> CapsuleFileResult {
    CapsuleFileResult(path: path, status: status, fileHash: fileHash)
  }
}
