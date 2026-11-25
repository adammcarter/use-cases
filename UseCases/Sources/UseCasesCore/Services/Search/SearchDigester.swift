/// SHA-256 over bytes that are the same on every system.
struct SearchDigester: SearchDigesting {
  private let hasher: any Hashing
  private let writer: any StoreJSONWriting

  init(
    hasher: any Hashing = SHA256Hasher(),
    writer: any StoreJSONWriting = StoreJSONWriter(),
  ) {
    self.hasher = hasher
    self.writer = writer
  }

  func digest(
    of workspace: LoadedWorkspace,
    status: WorkspaceStatus,
    groupMembers: [String]?,
  ) -> String {
    let statuses = Dictionary(
      status.useCases.map { useCase in
        (useCase.identifier, useCase.status.rawValue)
      },
      uniquingKeysWith: { first, _ in
        first
      },
    )

    var bytes: [UInt8] = []

    for useCase in workspace.useCases {
      bytes += Array(useCase.identifier.text.utf8)
      bytes.append(0)
      bytes += Array(useCase.file.text.utf8)
      bytes.append(0)
      bytes += Array((statuses[useCase.identifier.text] ?? "").utf8)
      bytes.append(0)
      bytes += writer.compact(
        useCase.definition.document(identifier: useCase.identifier),
      )
      bytes.append(0x0A)
    }

    bytes += Array("group".utf8)

    if let groupMembers {
      for member in groupMembers {
        bytes.append(0)
        bytes += Array(member.utf8)
      }
    } else {
      bytes += Array(" none".utf8)
    }

    return hasher.sha256Hex(of: bytes)
  }

  func seal(
    of parameters: StoreJSONValue,
    state: String,
  ) -> String {
    hasher.sha256Hex(of: writer.compact(parameters) + [0x0A] + Array(state.utf8))
  }
}
