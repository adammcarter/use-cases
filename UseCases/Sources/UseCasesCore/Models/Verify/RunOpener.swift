/// Which request opened a verify run (`start.json`, chapter 12 §11). `verify --finish` finishes
/// only runs `verify --start` opened; a run `verify --run` opened is finished by that request
/// alone, and if it stopped first it can only be aborted (chapter 13 §6).
enum RunOpener: String, CaseIterable, Sendable {
  case start
  case run
}
