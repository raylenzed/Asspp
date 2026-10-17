import Foundation
import WebKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// A local WASM signing session. Only the SAP handshake uses the network.
@MainActor
public final class SAPWebSigner: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private var webView: WKWebView?
    private var ready = false
    private var continuation: CheckedContinuation<Data, Error>?
    private var request: (guid: String, body: Data)?
    private var timeout: Task<Void, Never>?
    private var networkTasks: [Task<Void, Never>] = []
    private let session: URLSession
    #if os(macOS)
    private var hostWindow: NSWindow?
    #endif

    public override init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration)
        super.init()
    }

    public func sign(_ data: Data, guid: String) async throws -> Data {
        try Task.checkCancellation()
        guard continuation == nil else { throw failure("SAP signer is already busy") }
        guard !data.isEmpty, guid.count == 12,
              guid.allSatisfy({ $0.isHexDigit })
        else { throw failure("Invalid SAP request or device identifier") }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                request = (guid, data)
                timeout = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: 180_000_000_000) }
                    catch { return }
                    self?.finish(.failure(self?.failure("Apple SAP signing timed out") ?? CancellationError()))
                }
                if ready { sendRequest() }
                else if webView == nil { loadRuntime() }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(.failure(CancellationError())) }
        }
    }

    public func close() {
        if continuation != nil { finish(.failure(CancellationError())) }
        ready = false
        webView?.stopLoading()
        webView?.configuration.userContentController.removeScriptMessageHandler(forName: "sap")
        webView?.removeFromSuperview()
        webView = nil
        #if os(macOS)
        hostWindow = nil
        #endif
        session.invalidateAndCancel()
    }

    private func loadRuntime() {
        trace("loading local resources")
        guard let directory = Bundle.module.url(forResource: "Runtime", withExtension: nil),
              FileManager.default.fileExists(atPath: directory.appendingPathComponent("sap.wasm").path)
        else {
            finish(.failure(failure("SAP resources are missing from this build")))
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(WeakHandler(self), name: "sap")
        configuration.setURLSchemeHandler(RuntimeAssets(directory: directory), forURLScheme: "asspp-sap")
        #if os(macOS)
        _ = NSApplication.shared
        #endif
        let view = WKWebView(frame: CGRect(x: 0, y: 0, width: 1, height: 1), configuration: configuration)
        view.navigationDelegate = self
        webView = view
        #if os(iOS)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        view.isUserInteractionEnabled = false
        view.alpha = 0.01
        window?.addSubview(view)
        #else
        let window = NSWindow(contentRect: view.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = view
        hostWindow = window
        #endif
        view.load(URLRequest(url: URL(string: "asspp-sap://runtime/index.html")!))
    }

    private func sendRequest() {
        guard let request else { return }
        call("sapSignRequest", arguments: [request.guid, request.body.base64EncodedString()])
    }

    private func call(_ function: String, arguments: [Any]) {
        do {
            let json = try JSONSerialization.data(withJSONObject: arguments)
            guard let argumentList = String(data: json, encoding: .utf8) else { return }
            webView?.evaluateJavaScript("window.\(function)(...\(argumentList)); undefined") { [weak self] _, error in
                if error != nil {
                    Task { @MainActor in
                        self?.finish(.failure(self?.failure("SAP runtime could not execute") ?? CancellationError()))
                    }
                }
            }
        } catch { finish(.failure(error)) }
    }

    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, message.webView === webView,
              let fields = message.body as? [String: String], let event = fields["event"]
        else { return }
        trace("event: \(event)")
        switch event {
        case "ready":
            ready = true
            sendRequest()
        case "signed":
            guard let value = fields["signature"], let signature = Data(base64Encoded: value),
                  !signature.isEmpty, signature.count <= 65536
            else {
                finish(.failure(failure("Apple SAP returned an invalid signature")))
                return
            }
            finish(.success(signature))
        case "failed":
            finish(.failure(failure(fields["message"] ?? "Apple SAP signing failed")))
        case "request":
            guard continuation != nil, let id = fields["id"], let kind = fields["kind"] else { return }
            handshake(id: id, kind: kind, body: fields["body"] ?? "")
        default:
            break
        }
    }

    private func handshake(id: String, kind: String, body: String) {
        let url: URL
        var payload: Data?
        switch kind {
        case "certificate":
            url = URL(string: "https://s.mzstatic.com/sap/setupCert.plist")!
        case "setup":
            guard let data = Data(base64Encoded: body), !data.isEmpty, data.count <= 65536 else {
                call("sapReply", arguments: [id, "", "Invalid SAP setup message"])
                return
            }
            url = URL(string: "https://fpinit.itunes.apple.com/v1/signSapSetup/legacy")!
            payload = data
        default:
            call("sapReply", arguments: [id, "", "Unsupported SAP transport"])
            return
        }
        var request = URLRequest(url: url)
        if let payload {
            request.httpMethod = "POST"
            request.httpBody = payload
            request.setValue("application/x-plist", forHTTPHeaderField: "Content-Type")
        }
        networkTasks.append(Task { [weak self, session] in
            do {
                let (data, response) = try await session.data(for: request)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse,
                      response.statusCode == 200, data.count <= 1_048_576
                else { throw self?.failure("Apple SAP setup returned an invalid response") ?? CancellationError() }
                self?.call("sapReply", arguments: [id, data.base64EncodedString(), ""])
            } catch {
                guard !Task.isCancelled else { return }
                self?.call("sapReply", arguments: [id, "", "Could not connect to Apple SAP setup"])
            }
        })
    }

    private func finish(_ result: Result<Data, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        request = nil
        timeout?.cancel()
        timeout = nil
        networkTasks.forEach { $0.cancel() }
        networkTasks.removeAll()
        if case .failure = result {
            ready = false
            webView?.stopLoading()
            webView?.configuration.userContentController.removeScriptMessageHandler(forName: "sap")
            webView?.removeFromSuperview()
            webView = nil
            #if os(macOS)
            hostWindow = nil
            #endif
        }
        continuation.resume(with: result)
    }

    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(.failure(failure("SAP runtime could not load")))
    }

    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(.failure(failure("SAP runtime could not load")))
    }

    public func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        ready = false
        if continuation != nil { finish(.failure(failure("SAP runtime was stopped by the system"))) }
        else { self.webView = nil }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "wiki.qaq.Asspp.SAP", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func trace(_ message: String) {
        if ProcessInfo.processInfo.environment["ASSPP_TEST_APPLE_SAP"] == "1" {
            print("SAP WebView: \(message)")
        }
    }
}

@MainActor
private final class WeakHandler: NSObject, WKScriptMessageHandler {
    private weak var owner: SAPWebSigner?
    init(_ owner: SAPWebSigner) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.userContentController(userContentController, didReceive: message)
    }
}

/// Serves only immutable bundled assets, avoiding file:// XMLHttpRequest restrictions.
@MainActor
private final class RuntimeAssets: NSObject, WKURLSchemeHandler {
    private let directory: URL
    private let types = [
        "index.html": "text/html",
        "bridge.js": "application/javascript",
        "unicorn_x86.js": "application/javascript",
        "wasm_exec.js": "application/javascript",
        "sap.wasm": "application/wasm",
    ]

    init(directory: URL) { self.directory = directory }

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let url = urlSchemeTask.request.url, url.scheme == "asspp-sap",
              url.host == "runtime", url.query == nil,
              let type = types[String(url.path.dropFirst())]
        else {
            urlSchemeTask.didFailWithError(URLError(.unsupportedURL))
            return
        }
        do {
            let data = try Data(contentsOf: directory.appendingPathComponent(url.lastPathComponent), options: .mappedIfSafe)
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: [
                "Content-Type": type + (type == "application/wasm" ? "" : "; charset=utf-8"),
                "Content-Length": "\(data.count)",
            ])!
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch { urlSchemeTask.didFailWithError(error) }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}
