import SwiftUI
import WebKit
import CoderSwitchCore

struct WebLoginView: View {
    let model: WebLoginModel
    let onDone: () -> Void

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
            Label(
                "Google sign-in may be blocked in embedded browsers. If it fails, use email login instead.",
                systemImage: "info.circle"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
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
