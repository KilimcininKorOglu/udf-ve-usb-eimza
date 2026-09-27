import Foundation
import WebKit
import SignCore

/// Bridges the web page's requests to the local signing service. Government
/// pages are HTTPS and cannot fetch the HTTP loopback directly (mixed
/// content), so the injected shim posts requests here and the native side
/// answers from the in-process router.
final class WebBridge: NSObject, WKScriptMessageHandler {
    static let handlerName = "signbridge"
    private let router: Router
    private weak var webView: WKWebView?
    private var streams: [String: Task<Void, Never>] = [:]

    init(router: Router) {
        self.router = router
    }

    func attach(to webView: WKWebView) {
        self.webView = webView
    }

    /// The script injected into every page: it wraps fetch and EventSource
    /// that target the loopback port and routes them through the native host.
    static var userScript: String {
        """
        (function(){
          var TARGET = ':5975';
          var origFetch = window.fetch ? window.fetch.bind(window) : null;
          var pending = {};
          var nextId = 1;
          window.__sbResolve = function(id, status, headersJson, bodyB64){
            var p = pending[id]; if(!p) return; delete pending[id];
            var bytes = Uint8Array.from(atob(bodyB64), function(c){ return c.charCodeAt(0); });
            var headers = {}; try{ headers = JSON.parse(headersJson); }catch(e){}
            p.resolve(new Response(bytes, {status: status, headers: headers}));
          };
          window.fetch = function(input, init){
            var url = (typeof input === 'string') ? input : input.url;
            if(url.indexOf(TARGET) === -1 && origFetch) return origFetch(input, init);
            init = init || {};
            var id = String(nextId++);
            var headers = {};
            try{ if(init.headers){ new Headers(init.headers).forEach(function(v,k){ headers[k]=v; }); } }catch(e){}
            var body = (typeof init.body === 'string') ? init.body : '';
            return new Promise(function(resolve, reject){
              pending[id] = {resolve: resolve, reject: reject};
              window.webkit.messageHandlers.signbridge.postMessage(
                {kind:'fetch', id:id, method:(init.method||'GET'), url:url, headers:headers, body:body});
            });
          };
        })();
        """
    }

    func userContentController(
        _ controller: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let dict = message.body as? [String: Any],
              let kind = dict["kind"] as? String else { return }
        if kind == "fetch" { handleFetch(dict) }
    }

    private func handleFetch(_ dict: [String: Any]) {
        guard let id = dict["id"] as? String,
              let urlString = dict["url"] as? String,
              let url = URL(string: urlString) else { return }
        let request = buildRequest(dict, url: url)
        Task { [weak self] in
            guard let self else { return }
            let outcome = await self.router.route(request)
            guard case .response(let response) = outcome else { return }
            await self.deliver(id: id, response: response)
        }
    }

    private func buildRequest(_ dict: [String: Any], url: URL) -> HTTPRequest {
        let method = (dict["method"] as? String ?? "GET").uppercased()
        let headers = (dict["headers"] as? [String: String]) ?? [:]
        let body = Data((dict["body"] as? String ?? "").utf8)
        let path = url.path.isEmpty ? "/" : url.path
        return HTTPRequest(method: method, path: path, query: [:], headers: headers, body: body)
    }

    @MainActor
    private func deliver(id: String, response: HTTPResponse) {
        let headersJSON = (try? JSONSerialization.data(withJSONObject: response.headers))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let bodyB64 = response.body.base64EncodedString()
        let escaped = headersJSON.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
        let js = "window.__sbResolve('\(id)', \(response.status), '\(escaped)', '\(bodyB64)');"
        webView?.evaluateJavaScript(js)
    }
}
