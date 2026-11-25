import Testing

struct CheckoutSmokeTests {
    // @use-case:shop.checkout.complete#app-smoke.checkout-smoke
    @Test
    func checkoutSmokeCreatesOrderAndShowsConfirmation() async throws {
        let app = AppController()
        let order = try await app.completeCheckout()

        #expect(order.id == "ORDER-123")
        #expect(app.confirmationOrderID == "ORDER-123")
    }
    // @use-case:end shop.checkout.complete#app-smoke.checkout-smoke
}
