import Foundation
import Observation
import WebKit
import CoderSwitchCore

/// Owns the login `WKWebView` for one account. The web view uses that account's own
/// cookie jar, so two accounts on the same site never share a sign-in.
@MainActor
@Observable
final class WebLoginModel: NSObject {
    let account: Account
    @ObservationIgnored let webView: WKWebView

    private(set) var host = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var loadError: String?

    init(account: Account) {
        self.account = account
        let webView = WKWebView(
            frame: .zero,
            configuration: WebSessionClient.shared.configuration(for: account.id)
        )
        webView.customUserAgent = WebSessionClient.userAgent
        webView.allowsBackForwardNavigationGestures = true
        self.webView = webView
        super.init()
        webView.navigationDelegate = self
        webView.uiDelegate = self
        host = account.webLoginURL?.host ?? ""
    }

    func load() {
        guard let url = account.webLoginURL else {
            loadError = "This account has no login page."
            return
        }
        loadError = nil
        webView.load(URLRequest(url: url))
    }

    func reload() {
        if webView.url == nil { load() } else { webView.reload() }
    }

    func goBack() {
        webView.goBack()
    }

    /// Stores cookies pasted from a normal browser in this account's jar, then reopens the
    /// login page so the user can see they are signed in.
    func importCookies(_ text: String) async throws -> Int {
        guard let siteURL = account.webLoginURL else {
            throw PastedCookieError.noCookies
        }
        let count = try await WebSessionClient.shared.importCookies(text, for: account.id, siteURL: siteURL)
        load()
        return count
    }

    func stop() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
    }

    private func syncState() {
        host = webView.url?.host ?? host
        canGoBack = webView.canGoBack
    }
}

extension WebLoginModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        loadError = nil
        syncState()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncState()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        syncState()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        fail(error)
    }

    private func fail(_ error: Error) {
        isLoading = false
        syncState()
        // Redirects cancel the first request; that is not a failure the user needs to see.
        if (error as NSError).code == NSURLErrorCancelled { return }
        loadError = error.localizedDescription
    }
}

extension WebLoginModel: WKUIDelegate {
    /// `target=_blank` and `window.open` load in this same view, so the sign-in stays in one window.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }
}
