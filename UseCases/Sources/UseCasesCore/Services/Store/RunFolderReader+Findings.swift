extension RunFolderReader {
  /// What has happened to the reports and attachments of a sealed run since it was sealed. None of
  /// it changes a verdict or makes the run unreadable (chapter 12 §15 and §17).
  func findings(
    in folder: StoreFile,
    completion: RunCompletion,
    results: [StoredResult],
  ) -> [RunIntegrityFinding] {
    reportFindings(
      in: folder,
      completion: completion,
    ) + attachmentFindings(
      in: folder,
      run: completion.identifier,
      results: results,
    )
  }

  private func reportFindings(
    in folder: StoreFile,
    completion: RunCompletion,
  ) -> [RunIntegrityFinding] {
    let reports = folder.appending(StoreLayout.reportsFolder)
    var findings: [RunIntegrityFinding] = []

    for report in completion.details?.reportDigests ?? [] {
      let streamed: StreamedFile?
      do {
        streamed = try access.streamedFile(
          below: reports,
          path: report.path,
          using: hasher,
        )
      } catch {
        findings.append(.reportChanged(
          run: completion.identifier,
          path: report.path,
        ))
        continue
      }

      guard let streamed else {
        findings.append(.reportMissing(
          run: completion.identifier,
          path: report.path,
        ))
        continue
      }
      if streamed.digest != report.digest {
        findings.append(.reportChanged(
          run: completion.identifier,
          path: report.path,
        ))
      }
    }

    return findings + addedReportFindings(
      in: reports,
      completion: completion,
    )
  }

  /// Files under `reports/` that the marker does not list: written after the run was sealed.
  private func addedReportFindings(
    in reports: StoreFile,
    completion: RunCompletion,
  ) -> [RunIntegrityFinding] {
    guard let found = try? access.files(below: reports) else {
      return []
    }

    let sealed = Set((completion.details?.reportDigests ?? []).map(\.path))

    return found.filter { path in
      !sealed.contains(path) && (try? access.kind(of: reports.appending(path))) == .file
    }.map { path in
      .reportAdded(
        run: completion.identifier,
        path: path,
      )
    }
  }

  private func attachmentFindings(
    in folder: StoreFile,
    run: RunIdentifier,
    results: [StoredResult],
  ) -> [RunIntegrityFinding] {
    var findings: [RunIntegrityFinding] = []

    for result in results {
      for attachment in result.detail?.attachments ?? [] {
        guard let damage = damage(
          of: attachment,
          in: folder,
        ) else {
          continue
        }

        findings.append(.attachmentDamaged(
          run: run,
          useCase: result.useCase,
          route: result.route,
          name: attachment.name,
          damage: damage,
        ))
      }
    }

    return findings
  }

  private func damage(
    of attachment: ResultAttachment,
    in folder: StoreFile,
  ) -> AttachmentDamage? {
    let streamed: StreamedFile?
    do {
      streamed = try access.streamedFile(
        below: folder,
        path: StoreLayout.attachmentPath(digest: attachment.digest),
        using: hasher,
      )
    } catch {
      return .unreadable
    }

    guard let streamed else {
      return .missing
    }
    guard streamed.length == attachment.sizeBytes else {
      return .wrongSize(
        expected: attachment.sizeBytes,
        found: streamed.length,
      )
    }

    return streamed.digest == attachment.digest ? nil : .wrongDigest
  }
}
