#if os(macOS)
import AppleActionSigner
import Foundation
import XCTest

final class AppleActionSignerTests: XCTestCase {
    func testSystemSigningSession() async throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ASSPP_TEST_APPLE_SAP"] == "1",
            "Set ASSPP_TEST_APPLE_SAP=1 to exercise CommerceKit on a Mac"
        )
        let signature = try await Task.detached {
            var error: NSError?
            let signature = AssppSignAppleAction(Data("Asspp SAP smoke test".utf8), &error)
            if let error { throw error }
            return signature
        }.value
        XCTAssertFalse(try XCTUnwrap(signature).isEmpty)
    }
}
#endif
