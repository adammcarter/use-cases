import Foundation

/// Reads the file once and hands its text to the settings reader.
struct ScopeSettingsLoader: ScopeSettingsLoading {
  private let fileSystem: any FileSystemReading
  private let settingsReader: any ScopeSettingsReading

  init(
    fileSystem: any FileSystemReading,
    settingsReader: any ScopeSettingsReading,
  ) {
    self.fileSystem = fileSystem
    self.settingsReader = settingsReader
  }

  func loadSettings(
    at file: URL,
    path: WorkspacePath,
  ) throws(ScopeSettingsLoadingError) -> ScopeSettings {
    let text: String

    do {
      text = try fileSystem.readText(at: file)
    } catch {
      throw .unreadable(error)
    }

    do {
      return try settingsReader.readSettings(
        fromText: text,
        at: path,
      )
    } catch {
      throw .invalid(error)
    }
  }
}
