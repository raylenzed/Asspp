@testable import ApplePackage
import Foundation
import XCTest

final class AuthenticationDestinationTests: XCTestCase {
    func testCredentialsStayOnAppleAuthenticationEndpoints() throws {
        let path = "/WebObjects/MZFinance.woa/wa/authenticate/"
        for host in ["buy.itunes.apple.com", "p42-buy.itunes.apple.com"] {
            XCTAssertTrue(Authenticator.isTrustedAuthEndpoint(try XCTUnwrap(URL(string: "https://\(host)\(path)"))))
        }
        for destination in [
            "http://buy.itunes.apple.com\(path)",
            "https://buy.itunes.apple.com.attacker.example\(path)",
            "https://buy.itunes.apple.com:8443\(path)",
            "https://username@buy.itunes.apple.com\(path)",
            "https://buy.itunes.apple.com/unrelated",
            "https://auth.itunes.apple.com/auth/v1/native/fast/",
        ] {
            XCTAssertFalse(Authenticator.isTrustedAuthEndpoint(try XCTUnwrap(URL(string: destination))))
        }
    }
}
