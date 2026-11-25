import Foundation

/// Reads file content from a file system.
struct FileContentReader: FileContentReading {
  let fileSystem: any FileSystemReading

  func bytes(
    of file: WorkspacePath,
    in context: DiscoveryContext,
  ) throws(FileContentError) -> [UInt8] {
    let location = context.url(for: file)
    let kind = try kindOfReadable(at: location)

    do {
      switch kind {
      case .symlink:
        return try Array(fileSystem.targetText(ofSymlinkAt: location).utf8)
      default:
        return try fileSystem.readBytes(at: location)
      }
    } catch {
      throw FileContentError(reading: error)
    }
  }

  func chunks(
    of file: WorkspacePath,
    in context: DiscoveryContext,
  ) throws(FileContentError) -> any FileChunkReading {
    let location = context.url(for: file)

    switch try kindOfReadable(at: location) {
    case .symlink:
      return try BufferedChunkReader(bytes: Array(targetText(ofSymlinkAt: location).utf8))
    default:
      do {
        return try fileSystem.chunks(of: location)
      } catch {
        throw FileContentError(reading: error)
      }
    }
  }

  /// Says whether the thing at `location` is a file or a symlink, which are what can be read.
  private func kindOfReadable(at location: URL) throws(FileContentError) -> FileEntryKind {
    let kind: FileEntryKind?

    do {
      kind = try fileSystem.kindOfItem(at: location)
    } catch {
      throw .unreadable(error)
    }

    switch kind {
    case .file?:
      return .file
    case .symlink?:
      return .symlink
    case let kind?:
      throw .notAFile(kind)
    case nil:
      throw .missing
    }
  }

  private func targetText(ofSymlinkAt link: URL) throws(FileContentError) -> String {
    do {
      return try fileSystem.targetText(ofSymlinkAt: link)
    } catch {
      throw FileContentError(reading: error)
    }
  }
}
