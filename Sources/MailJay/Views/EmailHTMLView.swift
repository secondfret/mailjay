import AppKit
import SwiftUI
import WebKit

struct EmailHTMLView: NSViewRepresentable {
    let html: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        guard context.coordinator.loadedHTML != html else { return }
        context.coordinator.loadedHTML = html
        webView.loadHTMLString(EmailHTMLDocument.make(from: html), baseURL: nil)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url,
               ["http", "https", "mailto"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}

enum EmailHTMLDocument {
    static func make(from source: String) -> String {
        let safeSource = source.replacingOccurrences(
            of: #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            with: "",
            options: .regularExpression
        )
        let head = """
        <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src data:; style-src 'unsafe-inline'; font-src data:; base-uri 'none'; form-action 'none'">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          html { color-scheme: dark; background: #222222; }
          body {
            box-sizing: border-box;
            margin: 0;
            padding: 8px 20px 24px;
            color: rgba(255,255,255,0.88);
            background: #222222;
            font: 15px -apple-system, BlinkMacSystemFont, sans-serif;
            line-height: 1.55;
            overflow-wrap: anywhere;
          }
          a { color: #60A5FA; }
          img { max-width: 100% !important; height: auto !important; }
          table { max-width: 100% !important; }
          pre { white-space: pre-wrap; }
        </style>
        """

        if let headTag = safeSource.range(of: #"(?i)<head(?:\s[^>]*)?>"#, options: .regularExpression) {
            var document = safeSource
            document.insert(contentsOf: head, at: headTag.upperBound)
            return document
        }

        return "<!doctype html><html><head>\(head)</head><body>\(safeSource)</body></html>"
    }
}
