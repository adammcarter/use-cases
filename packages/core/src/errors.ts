export class PresentationSkillsError extends Error {
  constructor(
    message: string,
    readonly code: string
  ) {
    super(message);
    this.name = "PresentationSkillsError";
  }
}
