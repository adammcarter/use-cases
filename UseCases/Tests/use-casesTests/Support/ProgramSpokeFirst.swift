/// The program said something, or ended, before the test it was to run was held: what it said.
struct ProgramSpokeFirst: Error, CustomStringConvertible {
  let said: String

  var description: String {
    "the program spoke before its test was held: \(said)"
  }
}
