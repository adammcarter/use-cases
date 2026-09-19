import Testing
@testable import UseCasesCore

/// The CLI's up-front key checks: ed25519 PEMs only, a private key accepted
/// where a public one is asked for, as node's `createPublicKey` accepts it.
struct Ed25519KeyMaterialTests {
  @Test
  func `accepts a generated keypair in each role it can fill`() {
    let keypair = SigningKeyGeneration.generate()

    #expect(Ed25519KeyMaterial.isPublicKey(pem: keypair.publicPEM))
    #expect(Ed25519KeyMaterial.isPublicKey(pem: keypair.privatePEM))
    #expect(Ed25519KeyMaterial.isPrivateKey(pem: keypair.privatePEM))
    #expect(!Ed25519KeyMaterial.isPrivateKey(pem: keypair.publicPEM))
  }

  @Test(arguments: [
    "",
    "garbage\n",
    "-----BEGIN PUBLIC KEY-----\nnot base64!\n-----END PUBLIC KEY-----\n",
    "-----BEGIN PUBLIC KEY-----\nMCowBQ==\n-----END PUBLIC KEY-----\n",
  ])
  func `refuses text that is no ed25519 key`(pem: String) {
    #expect(!Ed25519KeyMaterial.isPublicKey(pem: pem))
    #expect(!Ed25519KeyMaterial.isPrivateKey(pem: pem))
  }
}
