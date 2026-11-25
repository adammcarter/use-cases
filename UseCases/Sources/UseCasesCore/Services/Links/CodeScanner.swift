/// Walks the workspace on a file system and scans every file it may read with a marker scanner.
struct CodeScanner: CodeScanning {
  let fileSystem: any FileSystemReading
  let markerScanner: any MarkerScanning

  func scan(
    _ workspace: LoadedWorkspace,
    excluding context: DiscoveryContext,
  ) -> CodeScan {
    let walk = CodeFileWalker(fileSystem: fileSystem).walk(
      workspace,
      excluding: context,
    )
    var found = CodeScan(
      regions: [],
      diagnostics: walk.diagnostics,
    )

    for file in walk.files {
      scan(
        file,
        context: context,
        found: &found,
      )
    }

    return found
  }

  private func scan(
    _ file: WalkedFile,
    context: DiscoveryContext,
    found: inout CodeScan,
  ) {
    let location = context.url(for: file.path)
    let bytes: [UInt8]

    do {
      switch file.kind {
      case .symlink:
        bytes = try Array(fileSystem.targetText(ofSymlinkAt: location).utf8)
      case .file:
        bytes = try fileSystem.readBytes(at: location)
      }
    } catch .notFound {
      // A file that has gone since the walk is no longer in the workspace: another program, or
      // another write of Use Cases, took it away or swapped it for a new one.
      return
    } catch {
      found.diagnostics.append(.unreadableFile(file.path, because: error))
      return
    }

    let scanned = markerScanner.scan(
      bytes,
      in: file.path,
    )

    found.diagnostics += scanned.diagnostics
    found.regions += scanned.regions.map { region in
      FileRegion(
        file: file.path,
        region: region,
      )
    }
  }
}
