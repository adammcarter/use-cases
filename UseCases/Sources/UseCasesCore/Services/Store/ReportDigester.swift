/// Digests report files with SHA-256, one regular file at a time and a chunk of it at a time,
/// looking at every name with `lstat` first.
struct ReportDigester: ReportDigesting {
  private let access: any StoreFileAccessing
  private let hasher: any Hashing

  init(
    access: any StoreFileAccessing,
    hasher: any Hashing = SHA256Hasher(),
  ) {
    self.access = access
    self.hasher = hasher
  }

  func digests(
    below folder: StoreFile,
    prefix: String,
  ) -> ReportDigests {
    let paths: [String]

    do {
      paths = try access.files(below: folder)
    } catch {
      return ReportDigests(
        digests: [],
        unusable: [Self.cannotBeListed(prefix: prefix, error)],
      )
    }

    var digests: [FileDigest] = []
    var unusable: [UnusableReportEntry] = []

    for path in paths {
      guard isRegular(folder.appending(path)) else {
        unusable.append(Self.notRegular(prefix + path))
        continue
      }

      do {
        guard let streamed = try access.streamedFile(
          below: folder,
          path: path,
          using: hasher,
        ) else {
          unusable.append(Self.gone(prefix + path))
          continue
        }

        digests.append(
          FileDigest(
            path: prefix + path,
            digest: streamed.digest,
          ),
        )
      } catch {
        unusable.append(Self.unreadable(prefix + path, error))
      }
    }

    return ReportDigests(
      digests: digests,
      unusable: unusable,
    )
  }

  func unusableEntries(below folder: StoreFile) -> [UnusableReportEntry] {
    let paths: [String]

    do {
      paths = try access.files(below: folder)
    } catch {
      return [Self.cannotBeListed(prefix: "", error)]
    }

    return paths.filter { path in
      !isRegular(folder.appending(path))
    }.map(Self.notRegular)
  }

  private func isRegular(_ file: StoreFile) -> Bool {
    (try? access.kind(of: file)) == .file
  }

  private static func notRegular(_ path: String) -> UnusableReportEntry {
    UnusableReportEntry(
      path: path,
      reason: "is not a regular file (a symlink or a special file); it is never followed",
    )
  }

  private static func gone(_ path: String) -> UnusableReportEntry {
    UnusableReportEntry(
      path: path,
      reason: "went missing while it was digested",
    )
  }

  private static func unreadable(
    _ path: String,
    _ problem: StoreProblem,
  ) -> UnusableReportEntry {
    UnusableReportEntry(
      path: path,
      reason: "cannot be read: \(problem)",
    )
  }

  private static func cannotBeListed(
    prefix: String,
    _ problem: StoreProblem,
  ) -> UnusableReportEntry {
    UnusableReportEntry(
      path: prefix.isEmpty ? "." : String(prefix.dropLast()),
      reason: "cannot be listed: \(problem)",
    )
  }
}
