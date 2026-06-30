export class UseCasesPluginError extends Error {
  constructor(
    message: string,
    readonly code: string
  ) {
    super(message);
    this.name = "UseCasesPluginError";
  }
}
