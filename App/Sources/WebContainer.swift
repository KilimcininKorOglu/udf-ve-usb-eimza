import SwiftUI
import WebKit
import SignCore

#if os(macOS)
typealias PlatformViewRepresentable = NSViewRepresentable
#else
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// A WKWebView wrapper for both macOS and iOS that installs the signing
/// bridge and loads the selected site.
struct WebContainer: PlatformViewRepresentable {
    let url: URL
    let router: Router

    func makeCoordinator() -> WebBridge {
        WebBridge(router: router)
    }

    private func makeWebView(_ bridge: WebBridge) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let script = WKUserScript(
            source: WebBridge.userScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        configuration.userContentController.addUserScript(script)
        configuration.userContentController.add(bridge, name: WebBridge.handlerName)
        let webView = WKWebView(frame: .zero, configuration: configuration)
        bridge.attach(to: webView)
        webView.load(URLRequest(url: url))
        return webView
    }

    #if os(macOS)
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateNSView(_ webView: WKWebView, context: Context) {}
    #else
    func makeUIView(context: Context) -> WKWebView { makeWebView(context.coordinator) }
    func updateUIView(_ webView: WKWebView, context: Context) {}
    #endif
}
