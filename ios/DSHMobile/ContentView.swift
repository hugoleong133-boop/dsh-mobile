import SwiftUI
import UIKit
import WebKit
import UniformTypeIdentifiers

/// 装包后肉眼核对版本用：构建号 = git 提交短哈希
enum AppInfo {
    static var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

struct RootView: View {
    @EnvironmentObject private var store: EndpointStore

    var body: some View {
        if store.activeURL != nil {
            SessionView()
                .ignoresSafeArea(.container, edges: .bottom)
        } else {
            ChannelPickerView()
        }
    }
}

// MARK: - 延迟胶囊

struct LatencyBadge: View {
    let latency: Int?
    var connected: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.08), lineWidth: 0.5))
    }

    private var label: String {
        if !connected { return "未连接" }
        guard let latency else { return "连接中…" }
        return "\(latency) ms"
    }

    private var dotColor: Color {
        guard connected else { return .gray }
        guard let latency else { return .yellow }
        if latency < 80 { return .green }
        if latency < 250 { return .yellow }
        return .red
    }
}

// MARK: - 通道选择

struct ChannelPickerView: View {
    @EnvironmentObject private var store: EndpointStore
    @State private var showSettings = false

    var body: some View {
        ZStack {
            Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

            VStack(spacing: 0) {
                LatencyBadge(latency: nil, connected: false)
                    .padding(.top, 8)

                Spacer(minLength: 0)

                VStack(spacing: 12) {
                    ForEach(DSHChannel.allCases) { channel in
                        ChannelButton(channel: channel)
                    }
                }
                .padding(.horizontal, 24)

                Spacer(minLength: 0)

                Button {
                    showSettings = true
                } label: {
                    Text("设置")
                        .font(.system(size: 15, weight: .medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 24)
                .padding(.bottom, 10)

                Text(AppInfo.versionLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary.opacity(0.45))
                    .padding(.bottom, 12)
            }
        }
        .sheet(isPresented: $showSettings) {
            ChannelSettingsView()
                .environmentObject(store)
        }
    }
}

struct ChannelButton: View {
    let channel: DSHChannel
    @EnvironmentObject private var store: EndpointStore
    @State private var showSettings = false

    private var configured: Bool { store.isConfigured(channel) }

    var body: some View {
        Button {
            if configured {
                store.connect(channel)
            } else {
                showSettings = true
            }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(channel.title)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(store.url(for: channel)?.absoluteString ?? "未设置")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 8)
                Image(systemName: configured ? "chevron.right" : "plus.circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(configured ? Color.secondary : Color(red: 0.29, green: 0.42, blue: 1.0))
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configured ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(configured ? Color.clear : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showSettings) {
            ChannelSettingsView()
                .environmentObject(store)
        }
    }
}

// MARK: - 设置

struct ChannelSettingsView: View {
    @EnvironmentObject private var store: EndpointStore
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [DSHChannel: String] = [:]
    @State private var error: String?

    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.09).ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(DSHChannel.allCases) { channel in
                            VStack(alignment: .leading, spacing: 7) {
                                HStack {
                                    Text(channel.title)
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                    Spacer()
                                    if !(drafts[channel] ?? "").isEmpty {
                                        Button("清除") {
                                            drafts[channel] = ""
                                        }
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                    }
                                }

                                TextField(channel.placeholder, text: binding(for: channel))
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .keyboardType(.URL)
                                    .font(.system(size: 13, design: .monospaced))
                                    .padding(12)
                                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))

                                Text(channel.caption)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error {
                            Text(error)
                                .font(.system(size: 12))
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("通道地址")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .font(.system(size: 16, weight: .semibold))
                }
            }
        }
        .onAppear(perform: loadDrafts)
    }

    private func binding(for channel: DSHChannel) -> Binding<String> {
        Binding(
            get: { drafts[channel] ?? "" },
            set: { drafts[channel] = $0; error = nil }
        )
    }

    private func loadDrafts() {
        var loaded: [DSHChannel: String] = [:]
        for channel in DSHChannel.allCases {
            loaded[channel] = store.url(for: channel)?.absoluteString ?? ""
        }
        drafts = loaded
    }

    private func save() {
        do {
            for channel in DSHChannel.allCases {
                try store.save(drafts[channel] ?? "", for: channel)
            }
            error = nil
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }
}

// MARK: - 会话

struct SessionView: View {
    @EnvironmentObject private var store: EndpointStore
    @State private var showMenu = false
    @State private var showSettings = false
    @State private var reloadToken = 0
    @State private var failure: String?

    private var url: URL? { store.activeURL }

    var body: some View {
        ZStack(alignment: .top) {
            if let url {
                WebContainer(
                    url: url,
                    reloadToken: reloadToken,
                    failure: $failure,
                    onLatency: { store.latency = $0 }
                )
                .ignoresSafeArea(edges: .bottom)
            }

            if let failure, let url {
                FailurePanel(
                    url: url,
                    message: failure,
                    onRetry: {
                        self.failure = nil
                        reloadToken += 1
                    },
                    onSwitch: { store.disconnect() }
                )
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // 顶部：中间延迟 / 右侧菜单
            ZStack {
                LatencyBadge(latency: store.latency, connected: true)
                HStack {
                    Spacer()
                    Button {
                        showMenu = true
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.system(size: 21))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 2)
        }
        .confirmationDialog("DSH Mobile", isPresented: $showMenu, titleVisibility: .visible) {
            Button("重新加载") {
                failure = nil
                reloadToken += 1
            }
            Button("切换通道") { store.disconnect() }
            Button("通道设置") { showSettings = true }
            if let url { Button("在 Safari 打开") { UIApplication.shared.open(url) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text((store.active?.title ?? "") + " · " + AppInfo.versionLabel)
        }
        .sheet(isPresented: $showSettings) {
            ChannelSettingsView()
                .environmentObject(store)
        }
    }
}

struct FailurePanel: View {
    let url: URL
    let message: String
    let onRetry: () -> Void
    let onSwitch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                Text("打不开这个地址").font(.system(size: 17, weight: .semibold))
            }
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button("重试", action: onRetry).buttonStyle(.borderedProminent)
                Button("切换通道", action: onSwitch).buttonStyle(.bordered)
                Button("在 Safari 打开") { UIApplication.shared.open(url) }.buttonStyle(.bordered)
            }
            .font(.system(size: 14))
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - WebView 壳

/// WKWebView 默认不工作、但 DSH 前端实际用到的东西，这里逐个补上：
///   文件选择器 / alert-confirm-prompt / 剪贴板兜底 / blob 下载 / window.open
/// 另外定期在页面内 fetch /__m/status 测 RTT，回传给原生显示在顶部。
struct WebContainer: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    @Binding var failure: String?
    let onLatency: (Int?) -> Void

    static let pingJS = #"""
    (function () {
      if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.dshmPing) return;
      var t0 = performance.now();
      fetch('/__m/status?_=' + Date.now(), { cache: 'no-store', credentials: 'same-origin' })
        .then(function (r) {
          var ms = Math.round(performance.now() - t0);
          window.webkit.messageHandlers.dshmPing.postMessage(r.ok ? ms : -1);
        })
        .catch(function () {
          window.webkit.messageHandlers.dshmPing.postMessage(-1);
        });
    })();
    """#

    static let bootstrapJS = #"""
    (function () {
      if (window.__dshmBridgeInstalled) return;
      window.__dshmBridgeInstalled = true;

      // ---- 剪贴板兜底：http 下 navigator.clipboard 不存在 ----
      function fallbackWriteText(text) {
        return new Promise(function (resolve, reject) {
          try {
            var ta = document.createElement('textarea');
            ta.value = text;
            ta.setAttribute('readonly', '');
            ta.style.cssText = 'position:fixed;top:0;left:0;opacity:0;';
            document.body.appendChild(ta);
            ta.select();
            ta.setSelectionRange(0, ta.value.length);
            var ok = document.execCommand('copy');
            document.body.removeChild(ta);
            ok ? resolve() : reject(new Error('execCommand copy failed'));
          } catch (e) { reject(e); }
        });
      }

      if (!window.isSecureContext || !navigator.clipboard || !navigator.clipboard.writeText) {
        try {
          Object.defineProperty(navigator, 'clipboard', {
            configurable: true,
            value: {
              writeText: fallbackWriteText,
              readText: function () { return Promise.reject(new Error('unsupported')); },
              write: function (items) {
                return Promise.all(items.map(function (item) {
                  if (item.getType && item.types && item.types.indexOf('text/plain') >= 0) {
                    return item.getType('text/plain').then(function (b) { return b.text(); }).then(fallbackWriteText);
                  }
                  return Promise.resolve();
                }));
              }
            }
          });
        } catch (e) { /* 保持原样 */ }
      }

      // ---- blob 下载桥接 ----
      var objectUrls = {};
      var nativeCreate = URL.createObjectURL.bind(URL);
      URL.createObjectURL = function (obj) {
        var u = nativeCreate(obj);
        try { objectUrls[u] = obj; } catch (e) {}
        return u;
      };

      function sendToNative(name, blob) {
        if (!window.webkit || !window.webkit.messageHandlers || !window.webkit.messageHandlers.dshmSave) return false;
        var reader = new FileReader();
        reader.onloadend = function () {
          var dataUrl = String(reader.result || '');
          var comma = dataUrl.indexOf(',');
          window.webkit.messageHandlers.dshmSave.postMessage({
            name: name || ('dsh-' + Date.now()),
            mime: (blob && blob.type) || '',
            data: comma >= 0 ? dataUrl.slice(comma + 1) : ''
          });
        };
        reader.readAsDataURL(blob);
        return true;
      }

      document.addEventListener('click', function (event) {
        var node = event.target;
        while (node && node !== document && !(node.tagName === 'A' && node.hasAttribute && node.hasAttribute('download'))) {
          node = node.parentElement;
        }
        if (!node || node === document || !node.hasAttribute('download')) return;
        var href = node.getAttribute('href') || '';
        var name = node.getAttribute('download') || 'download';
        if (!href) return;

        if (href.indexOf('blob:') === 0 || href.indexOf('data:') === 0) {
          event.preventDefault();
          event.stopPropagation();
          if (href.indexOf('blob:') === 0 && objectUrls[href]) {
            sendToNative(name, objectUrls[href]);
          } else if (href.indexOf('data:') === 0) {
            var comma = href.indexOf(',');
            var meta = href.slice(5, comma);
            window.webkit.messageHandlers.dshmSave.postMessage({
              name: name, mime: meta.split(';')[0],
              data: comma >= 0 ? href.slice(comma + 1) : ''
            });
          }
        }
      }, true);
    })();
    """#

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = config.userContentController
        controller.add(context.coordinator, name: "dshmSave")
        controller.add(context.coordinator, name: "dshmPing")
        controller.addUserScript(WKUserScript(
            source: Self.bootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))

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

    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stopPinging()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "dshmSave")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "dshmPing")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIDocumentPickerDelegate {
        private let parent: WebContainer
        private var loadedKey = ""
        private var openPanelCompletion: (([URL]?) -> Void)?
        private var pingTimer: Timer?

        init(_ parent: WebContainer) {
            self.parent = parent
        }

        func load(_ url: URL, token: Int, in view: WKWebView) {
            let key = "\(url.absoluteString)#\(token)"
            guard key != loadedKey else { return }
            loadedKey = key
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            view.load(request)
        }

        // MARK: 延迟探测

        func startPinging(_ webView: WKWebView) {
            stopPinging()
            ping(webView)
            let timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self, weak webView] _ in
                guard let self, let webView else { return }
                self.ping(webView)
            }
            timer.tolerance = 1
            pingTimer = timer
        }

        func stopPinging() {
            pingTimer?.invalidate()
            pingTimer = nil
        }

        private func ping(_ webView: WKWebView) {
            webView.evaluateJavaScript(WebContainer.pingJS, completionHandler: nil)
        }

        // MARK: 导航

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            parent.failure = nil
            startPinging(webView)
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
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            stopPinging()
            parent.onLatency(nil)

            var text = "\(ns.localizedDescription)（\(ns.domain) \(ns.code)）"
            if ns.code == -1022 || ns.code == -1004 || ns.code == -1009 || ns.code == -1001 {
                text += "\n\n检查电脑上 8765 是否在跑，以及这个网络能不能到该地址。"
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
            if target.scheme == "http" || target.scheme == "https" || target.scheme == "about"
                || target.scheme == "blob" || target.scheme == "data" {
                if navigationAction.targetFrame == nil {
                    webView.load(navigationAction.request)
                    decisionHandler(.cancel)
                    return
                }
                decisionHandler(.allow)
                return
            }
            UIApplication.shared.open(target)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.request.url != nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        // MARK: 文件选择器

        @available(iOS 18.4, *)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            openPanelCompletion = completionHandler
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .image, .movie, .audio, .text, .pdf, .data],
                asCopy: true
            )
            picker.allowsMultipleSelection = parameters.allowsMultipleSelection
            picker.delegate = self
            topViewController()?.present(picker, animated: true)
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            openPanelCompletion?(urls)
            openPanelCompletion = nil
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            openPanelCompletion?(nil)
            openPanelCompletion = nil
        }

        // MARK: 消息桥

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            if message.name == "dshmPing" {
                let value = (message.body as? NSNumber)?.intValue ?? -1
                parent.onLatency(value >= 0 ? value : nil)
                return
            }

            guard message.name == "dshmSave",
                  let body = message.body as? [String: Any],
                  let data = body["data"] as? String else { return }

            let rawName = (body["name"] as? String) ?? "download"
            let name = rawName.contains(".") ? rawName : rawName + ".bin"
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            guard let bytes = Data(base64Encoded: data, options: .ignoreUnknownCharacters) else { return }
            try? bytes.write(to: temp)

            let activity = UIActivityViewController(activityItems: [temp], applicationActivities: nil)
            if let host = topViewController() {
                activity.popoverPresentationController?.sourceView = host.view
                host.present(activity, animated: true)
            }
        }

        // MARK: 原生对话框

        private func topViewController() -> UIViewController? {
            let scene = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .first { $0.activationState == .foregroundActive }
                ?? UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            var controller = scene?.windows.first(where: \.isKeyWindow)?.rootViewController
            while let presented = controller?.presentedViewController {
                controller = presented
            }
            return controller
        }

        private func present(_ alert: UIAlertController,
                             from webView: WKWebView?,
                             fallback: @escaping () -> Void) {
            let host = webView?.window?.rootViewController ?? topViewController()
            guard let host else {
                fallback()
                return
            }
            if host.presentedViewController != nil {
                host.dismiss(animated: false)
            }
            host.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
            present(alert, from: webView) { completionHandler() }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "确定", style: .destructive) { _ in completionHandler(true) })
            present(alert, from: webView) { completionHandler(false) }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { field in field.text = defaultText }
            alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            present(alert, from: webView) { completionHandler(nil) }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadedKey = ""
            parent.failure = nil
            webView.reload()
        }
    }
}
