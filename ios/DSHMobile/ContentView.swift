import SwiftUI
import UIKit
import WebKit

struct RootView: View {
    @EnvironmentObject private var store: EndpointStore

    var body: some View {
        if let endpoint = store.active {
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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(LinearGradient(colors: [Color(red: 0.29, green: 0.42, blue: 1.0),
                                                      Color(red: 0.54, green: 0.29, blue: 1.0)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 64, height: 64)

                    Text("连接这台电脑").font(.system(size: 24, weight: .semibold))
                    Text("把电脑上 start.ps1 / tunnel.ps1 打印的地址填进来。可以填多个（每行一个），App 会按顺序尝试，第一个连上的就用。")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $store.pairInput)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .focused($focused)
                        .font(.system(size: 15, design: .monospaced))
                        .frame(minHeight: 110)
                        .padding(10)
                        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(alignment: .topLeading) {
                            if store.pairInput.isEmpty {
                                Text("192.168.1.124:8765/?k=123456\nhttps://xxx.ts.net/?k=123456")
                                    .font(.system(size: 15, design: .monospaced))
                                    .foregroundStyle(.secondary.opacity(0.6))
                                    .padding(.horizontal, 15)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }

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

                    Text("建议顺序：局域网 → tailnet → Funnel。排在前面的越快。")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .padding(24)
                .foregroundStyle(.white)
            }
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
    @State private var failure: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WebContainer(
                url: url,
                reloadToken: reloadToken,
                failure: $failure,
                onFailure: {
                    // 先清掉错误再试下一个；全部都失败才让面板出现
                    failure = nil
                    return store.advance()
                },
                onSuccess: { store.markGood() }
            )
            .ignoresSafeArea(edges: .bottom)

            if let failure {
                FailurePanel(
                    url: url,
                    message: failure,
                    onRetry: {
                        self.failure = nil
                        reloadToken += 1
                    },
                    onRestart: {
                        self.failure = nil
                        store.restart()
                        reloadToken += 1
                    },
                    onRepair: { store.forget() }
                )
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

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
            Button("重新加载") {
                failure = nil
                reloadToken += 1
            }
            Button("尝试下一个地址") {
                failure = nil
                if store.advance() { reloadToken += 1 }
            }
            Button("重新配对", role: .destructive) { store.forget() }
            Button("在 Safari 打开") { UIApplication.shared.open(url) }
            Button("取消", role: .cancel) {}
        } message: {
            Text(addressSummary)
        }
    }

    private var addressSummary: String {
        let list = store.endpoints.enumerated().map { index, item in
            (index == store.activeIndex ? "▶ " : "   ") + item.absoluteString
        }
        return list.joined(separator: "\n")
    }
}

/// 加载失败时顶替黑屏。原来没有失败回调，加载挂了就是一片黑，等于没有诊断信息。
struct FailurePanel: View {
    let url: URL
    let message: String
    let onRetry: () -> Void
    let onRestart: () -> Void
    let onRepair: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("打不开这个地址").font(.system(size: 17, weight: .semibold))
            }
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 10) {
                Button("重试", action: onRetry)
                    .buttonStyle(.borderedProminent)
                Button("全部重试", action: onRestart)
                    .buttonStyle(.bordered)
                Button("在 Safari 打开") { UIApplication.shared.open(url) }
                    .buttonStyle(.bordered)
                Button("重新配对", action: onRepair)
                    .buttonStyle(.bordered)
            }
            .font(.system(size: 14))

            Text("所有候选地址都试过了才显示这个面板。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

/// WKWebView 壳。所有导航都留在 App 内；只有 scheme 不是 http(s) 时交给系统。
struct WebContainer: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    @Binding var failure: String?
    let onFailure: () -> Bool
    let onSuccess: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

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
        context.coordinator.load(url, token: reloadToken, in: view)
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.load(url, token: reloadToken, in: view)
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private let parent: WebContainer
        private var loadedKey = ""

        init(_ parent: WebContainer) {
            self.parent = parent
        }

        /// 地址或 reloadToken 任一变化才重新加载，避免 SwiftUI 每帧都刷新
        func load(_ url: URL, token: Int, in view: WKWebView) {
            let key = "\(url.absoluteString)#\(token)"
            guard key != loadedKey else { return }
            loadedKey = key
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            view.load(request)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.failure = nil
            parent.onSuccess()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            report(error)
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            report(error)
        }

        private func report(_ error: Error) {
            let ns = error as NSError
            // 用户自己取消/重定向打断的不算失败
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }

            // 有下一个候选地址就直接切，别让用户看见错误
            if parent.onFailure() { return }

            var text = "\(ns.localizedDescription)（\(ns.domain) \(ns.code)）"
            if ns.code == -1022 || ns.code == -1004 || ns.code == -1009 || ns.code == -1001 {
                text += "\n\n无法建立连接。检查电脑上 8765 是否在跑（/__m/status），以及这个网络能不能到那个地址。"
            }
            parent.failure = text
        }

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
