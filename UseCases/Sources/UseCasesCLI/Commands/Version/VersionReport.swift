import Foundation
import UseCasesCore

/// What `use-cases --version` prints (chapter 16 §7): a line for people, one JSON
/// document for scripts.
struct VersionReport {
  private let version: ProductVersion

  init(version: ProductVersion) {
    self.version = version
  }

  func humanText() -> String {
    "use-cases \(version.release)"
  }

  func jsonText() throws(VersionReportError) -> String {
    let document = VersionDocument(
      outputVersion: OutputDocument.version,
      command: "version",
      version: version.release,
      contract: version.contract,
      store: version.store,
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

    let data: Data
    do {
      data = try encoder.encode(document)
    } catch {
      throw .encodingFailed
    }

    guard let text = String(
      data: data,
      encoding: .utf8,
    ) else {
      throw .encodingFailed
    }

    return text
  }
}

enum VersionReportError: Error {
  case encodingFailed
}

private struct VersionDocument: Encodable {
  let outputVersion: Int
  let command: String
  let version: String
  let contract: Int
  let store: Int

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case version
    case contract
    case store
  }
}
