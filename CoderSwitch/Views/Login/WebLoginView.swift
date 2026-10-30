import SwiftUI
import WebKit
import CoderSwitchCore

struct WebLoginView: View {
    let model: WebLoginModel
    let onDone: () -> Void

    @State private var isPastingCookie = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ZStack {
                WebViewHost(webView: model.webView)
                if let error = model.loadError {
                    ContentUnavailableView {
                        Label("Page did not load", systemImage: "wifi.exclamationmark")
                    } description: {
                        Text(error)
                    } actions: {
                        Button("Try again") { model.reload() }
                    }
                    .background(.background)
                }
            }
            Divider()
            footer
        }
        .sheet(isPresented: $isPastingCookie) {
            PasteCookieSheet(host: model.account.webLoginURL?.host ?? model.host) { text in
                try await model.importCookies(text)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Label(
                "Google sign-in is blocked in this window. Sign in with your normal browser, then paste its cookie.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Paste cookie…") { isPastingCookie = true }
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: model.goBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(!model.canGoBack)
            .help("Back")

            ProviderGlyph(provider: model.account.provider, size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(model.account.label)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                HStack(spacing: 4) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                    Text(model.host.isEmpty ? "Loading…" : model.host)
                        .lineLimit(1)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
            }
            Button(action: model.reload) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload")
            Button("Done", action: onDone)
                .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
