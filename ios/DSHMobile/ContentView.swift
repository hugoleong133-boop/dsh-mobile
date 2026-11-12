import SwiftUI
import UIKit
import WebKit

struct RootView: View {
    @EnvironmentObject private var store: EndpointStore

    var body: some View {
        if let endpoint = store.endpoint {
            SessionView(url: endpoint)
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            PairingView()
        }
    }
}

// MARK: - 配对

struct PairingView: View {
    @EnvironmentObject private var store: EndpointStore
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.42, blue: 1.0),
                                                  Color(red: 0.54, green: 0.29, blue: 1.0)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)

                Text("连接这台电脑").font(.system(size: 24, weight: .semibold))
                Text("在电脑上运行 dsh-mobile\\start.ps1，把打印出的地址填进来。之后这个 App 看到的就是电脑上同一个会话。")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)

                TextField("192.168.1.124:8765/?k=123456", text: $store.pairInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .focused($focused)
                    .font(.system(size: 16, design: .monospaced))
                    .padding(14)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))

                Button {
                    do {
                        try store.pair(from: store.pairInput)
                        error = nil
                    } catch {
                        self.error = error.localizedDescription
                    }
                } label: {
                    Text("连接").font(.system(size: 17, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(Color(red: 0.29, green: 0.42, blue: 1.0), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                if let error {
                    Text(error).font(.system(size: 13)).foregroundStyle(.red)
                }

                Spacer()
            }
            .padding(24)
            .foregroundStyle(.white)
        }
        .onAppear { focused = true }
    }
}

// MARK: - 会话

struct SessionView: View {
    let url: URL
    @EnvironmentObject private var store: EndpointStore
    @State private var showSettings = false
    @State private var reloadToken = 0

    var body: some View {
        WebContainer(url: url, reloadToken: reloadToken)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .topTrailing) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "ellipsis.circle.fill")
                        .font(.system(size: 22))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .padding(10)
                }
                .buttonStyle(.plain)
            }
            .confirmationDialog("DSH Mobile", isPresented: $showSettings, titleVisibility: .visible) {
                Button("重新加载") { reloadToken += 1 }
                Button("重新配对", role: .destructive) { store.forget() }
                Button("取消", role: .cancel) {}
            } message: {
                Text(url.absoluteString)
            }
    }
}

/// WKWebView 壳。所有导航都留在 App 内；只有 scheme 不是 http(s) 时交给系统。
struct WebContainer: UIViewRepresentable {
    let url: URL
    let reloadToken: Int

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        view.scrollView.keyboardDismissMode = .interactive
        view.scrollView.contentInsetAdjustmentBehavior = .never
        view.isOpaque = false
        view.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1)
        view.load(URLRequest(url: url))
        context.coordinator.loaded = reloadToken
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        guard context.coordinator.loaded != reloadToken else { return }
        context.coordinator.loaded = reloadToken
        view.load(URLRequest(url: url))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded = -1

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            if target.scheme == "http" || target.scheme == "https" || target.scheme == "about" {
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(target)
            decisionHandler(.cancel)
        }
    }
}
