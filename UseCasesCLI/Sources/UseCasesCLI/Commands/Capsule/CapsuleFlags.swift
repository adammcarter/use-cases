/// Flags more than one capsule command declares, defined once.
enum CapsuleFlags {
  static let capsule = FlagSpecification(
    key: "capsule",
    name: "--capsule",
    kind: .string,
    summary: "Capsule id.",
    valueName: "<id>",
    isRequired: true,
  )
}
