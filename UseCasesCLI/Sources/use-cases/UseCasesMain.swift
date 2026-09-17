import UseCasesCLI

@main
enum UseCasesMain {
  static func main() async {
    await UseCasesCommand.main()
  }
}
