import SwiftUI
import UIKit
import WebKit
import UniformTypeIdentifiers

/// 装包后肉眼核对版本用：构建号 = git 提交短哈希
enum AppInfo {
    static var versionLabel: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "v\(version) (\(build))"
    }
}

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

                    Text("DSH Mobile " + AppInfo.versionLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .center)
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
            Text(AppInfo.versionLabel + "\n\n" + addressSummary)
        }
    }

    private var addressSummary: String {
        store.endpoints.enumerated().map { index, item in
            (index == store.activeIndex ? "▶ " : "   ") + item.absoluteString
        }.joined(separator: "\n")
    }
}

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
                Button("重试", action: onRetry).buttonStyle(.borderedProminent)
                Button("全部重试", action: onRestart).buttonStyle(.bordered)
                Button("在 Safari 打开") { UIApplication.shared.open(url) }.buttonStyle(.bordered)
                Button("重新配对", action: onRepair).buttonStyle(.bordered)
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

// MARK: - WebView 壳

/// WKWebView 默认不工作、但 DSH 前端实际用到的东西，这里逐个补上：
///   1. `<input type="file">`        → runOpenPanelWith，否则点附件按钮毫无反应
///   2. `alert/confirm/prompt`       → 插件删除会话靠 confirm 二次确认
///   3. `navigator.clipboard`        → http 下不是安全上下文，注入 execCommand 兜底
///   4. blob: + `<a download>`       → WKWebView 不会下载，桥接到系统分享面板
///   5. `window.open` / target=_blank → 同窗口打开
struct WebContainer: UIViewRepresentable {
    let url: URL
    let reloadToken: Int
    @Binding var failure: String?
    let onFailure: () -> Bool
    let onSuccess: () -> Void

    /// 注入到页面最前面的补丁脚本
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

      var needsPolyfill = !window.isSecureContext || !navigator.clipboard || !navigator.clipboard.writeText;
      if (needsPolyfill) {
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
        } catch (e) { /* 定义失败就保持原样 */ }
      }

      // ---- blob 下载桥接：把 url 存下来，点击 <a download> 时读出内容发给原生 ----
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
        view.configuration.userContentController.removeScriptMessageHandler(forName: "dshmSave")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler, UIDocumentPickerDelegate {
        private let parent: WebContainer
        private var loadedKey = ""
        private var openPanelCompletion: (([URL]?) -> Void)?

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
            if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
            if parent.onFailure() { return }

            var text = "\(ns.localizedDescription)（\(ns.domain) \(ns.code)）"
            if ns.code == -1022 || ns.code == -1004 || ns.code == -1009 || ns.code == -1001 {
                text += "\n\n无法建立连接。检查电脑上 8765 是否在跑（/__m/status），以及这个网络能不能到那个地址。"
            }
            parent.failure = text
        }

        // MARK: 导航策略

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

        /// window.open / target=_blank：没有这个回调时点了什么都不发生
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
        //
        // `<input type="file">` 在 WKWebView 里不会自己弹面板，必须实现这个回调。
        // DSH 的附件上传就是靠它，缺了这一层，点附件按钮毫无反应。

        /// `<input type="file">` 在 WKWebView 里不会自己弹面板，必须实现这个回调。
        /// DSH 的附件上传就是靠它，缺了这一层，点附件按钮毫无反应。
        ///
        /// 注意：`WKOpenPanelParameters` 在当前 SDK 里标了 iOS 18.4+，
        /// 所以这里加可用性标注；低于 18.4 的系统上文件选择仍然不可用。
        @available(iOS 18.4, *)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            openPanelCompletion = completionHandler

            // WKOpenPanelParameters 只有 allowsMultipleSelection / allowsDirectories，
            // 拿不到 accept 列表，所以给一组通用类型，用户也能选"所有文件"。
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

        // MARK: blob 下载 → 系统分享

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
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

        /// present 失败时的兜底路径全都在这里；
        /// 优先用承载页面本身的窗口，比全局查找更不容易扑空。
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
