import AppleSAPRuntime
import Foundation
import XCTest

final class SAPWebSignerTests: XCTestCase {
    @MainActor
    func testLocalWebViewHandshakeAndSessionReuse() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ASSPP_TEST_APPLE_SAP"] == "1",
            "Set ASSPP_TEST_APPLE_SAP=1 to exercise the local WebView and Apple SAP setup"
        )
        let signer = SAPWebSigner()
        defer { signer.close() }
        let first: Data
        do {
            first = try await signer.sign(Data("Asspp SAP smoke test".utf8), guid: "AABBCCDDEEFF")
        } catch {
            let error = error as NSError
            print("SAP test error domain: \(error.domain), code: \(error.code), description: \(error.localizedDescription)")
            throw error
        }
        XCTAssertFalse(first.isEmpty)
        let second = try await signer.sign(Data("Asspp SAP second request".utf8), guid: "AABBCCDDEEFF")
        XCTAssertFalse(second.isEmpty)
        XCTAssertNotEqual(first, second)
    }
}
