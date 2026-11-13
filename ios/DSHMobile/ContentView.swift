import SwiftUI
import UIKit
import WebKit
import UniformTypeIdentifiers

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
            HomeView()
        }
    }
}

// MARK: - 延迟胶囊

struct LatencyBadge: View {
    let latency: Int?
    var connected: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 5)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 0.5))
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

// MARK: - 首页：选软件

struct HomeView: View {
    @EnvironmentObject private var store: EndpointStore
    @State private var path: [UUID] = []
    @State private var showManager = false
    @State private var renameTarget: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    header

                    if store.targets.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(store.targets) { target in
                                    Button {
                                        path.append(target.id)
                                    } label: {
                                        TargetCard(target: target)
                                    }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button {
                                            renameTarget = target.id
                                            renameText = target.name
                                        } label: {
                                            Label("重命名", systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            store.delete(target.id)
                                        } label: {
                                            Label("删除", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.top, 8)
                            .padding(.bottom, 28)
                        }
                    }

                    Text(AppInfo.versionLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary.opacity(0.40))
                        .padding(.bottom, 10)
                }
            }
            .navigationDestination(for: UUID.self) { id in
                ChannelListView(targetId: id)
            }
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showManager) {
            AppManagerView()
                .environmentObject(store)
        }
        .alert(
            "重命名",
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("名称", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let id = renameTarget { store.rename(id, to: renameText) }
                renameTarget = nil
            }
        }
    }

    private var header: some View {
        ZStack {
            LatencyBadge(latency: nil, connected: false)

            HStack {
                Button {
                    showManager = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    showManager = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.10), in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "square.stack.3d.up.slash")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary.opacity(0.5))
            Text("还没有添加软件")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("点左上角 + 添加一个")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            Spacer()
            Spacer()
        }
    }
}

struct TargetCard: View {
    let target: AppTarget

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 13, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Palette.accent(target.accent),
                            Palette.accent(target.accent).opacity(0.55),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 46, height: 46)
                .overlay(
                    Text(target.initial)
                        .font(.system(size: 20, weight: .bold))
                        .foregroundStyle(.white)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(target.name)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                Text(target.configuredCount > 0 ? "\(target.configuredCount) 条通道已配置" : "未配置地址")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.55))
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Palette.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Palette.cardStroke, lineWidth: 1)
        )
    }
}

// MARK: - 软件管理

struct AppManagerView: View {
    @EnvironmentObject private var store: EndpointStore
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""
    @State private var renameTarget: UUID?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
                List {
                    Section {
                        ForEach(store.targets) { target in
                            Button {
                                renameTarget = target.id
                                renameText = target.name
                            } label: {
                                HStack(spacing: 12) {
                                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                                        .fill(Palette.accent(target.accent))
                                        .frame(width: 30, height: 30)
                                        .overlay(
                                            Text(target.initial)
                                                .font(.system(size: 14, weight: .bold))
                                                .foregroundStyle(.white)
                                        )
                                    Text(target.name)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Text("\(target.configuredCount) 通道")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.white.opacity(0.07))
                        }
                        .onDelete { indexSet in
                            for index in indexSet { store.delete(store.targets[index].id) }
                        }
                    }

                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(Palette.accents[0])
                                .frame(width: 30, height: 30)
                            TextField("新增软件名称", text: $newName)
                                .foregroundStyle(.white)
                            Button("添加") {
                                store.addTarget(name: newName)
                                newName = ""
                            }
                            .font(.system(size: 14, weight: .semibold))
                            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .listRowBackground(Color.white.opacity(0.07))
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("软件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .alert(
                "重命名",
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("名称", text: $renameText)
                Button("取消", role: .cancel) { renameTarget = nil }
                Button("保存") {
                    if let id = renameTarget { store.rename(id, to: renameText) }
                    renameTarget = nil
                }
            }
        }
    }
}

// MARK: - 通道选择

struct ChannelListView: View {
    let targetId: UUID
    @EnvironmentObject private var store: EndpointStore
    @State private var showSettings = false

    private var target: AppTarget? { store.target(targetId) }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack {
                    LatencyBadge(
                        latency: store.latency,
                        connected: store.activeTargetId == targetId
                    )
                    HStack {
                        Spacer()
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.10), in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 14)

                ScrollView {
                    VStack(spacing: 12) {
                        ForEach(DSHChannel.allCases) { channel in
                            ChannelRow(
                                channel: channel,
                                url: store.url(in: targetId, channel: channel),
                                onConnect: { store.connect(targetId: targetId, channel: channel) },
                                onConfigure: { showSettings = true }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
                }
            }
        }
        .navigationTitle(target?.name ?? "通道")
        .navigationBarTitleDisplayMode(.large)
        .tint(Palette.accents[0])
        .sheet(isPresented: $showSettings) {
            ChannelSettingsView(targetId: targetId)
                .environmentObject(store)
        }
    }
}

struct ChannelRow: View {
    let channel: DSHChannel
    let url: URL?
    let onConnect: () -> Void
    let onConfigure: () -> Void

    private var configured: Bool { url != nil }

    var body: some View {
        Button {
            configured ? onConnect() : onConfigure()
        } label: {
            HStack(spacing: 14) {
                Image(systemName: channel.symbol)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(configured ? Palette.accents[0] : Color.secondary.opacity(0.7))
                    .frame(width: 38, height: 38)
                    .background(
                        RoundedRectangle(cornerRadius: 11, style: .continuous)
                            .fill(Color.white.opacity(configured ? 0.10 : 0.05))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white.opacity(configured ? 1 : 0.55))
                    Text(url?.absoluteString ?? "未设置")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                Image(systemName: configured ? "chevron.right" : "plus.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(configured ? Color.secondary.opacity(0.6) : Palette.accents[0])
            }
            .padding(15)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(configured ? Palette.cardFill : Palette.cardFillDim)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .stroke(configured ? Palette.cardStroke : Palette.cardStrokeDim, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 通道设置

struct ChannelSettingsView: View {
    let targetId: UUID
    @EnvironmentObject private var store: EndpointStore
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [DSHChannel: String] = [:]
    @State private var error: String?

    private var targetName: String {
        store.target(targetId)?.name ?? "通道"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Palette.background.ignoresSafeArea()
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
                                        Button("清除") { drafts[channel] = "" }
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
                                    .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.white.opacity(0.10), lineWidth: 1)
                                    )

                                Text(channel.caption)
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if let error {
                            Text(error).font(.system(size: 12)).foregroundStyle(.red)
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle(targetName)
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
            loaded[channel] = store.target(targetId)?.channels[channel.rawValue] ?? ""
        }
        drafts = loaded
    }

    private func save() {
        do {
            for channel in DSHChannel.allCases {
                try store.save(drafts[channel] ?? "", in: targetId, channel: channel)
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
            if let id = store.activeTargetId {
                Button("通道设置") { channelSettingsTarget = id; showSettings = true }
            }
            if let url { Button("在 Safari 打开") { UIApplication.shared.open(url) } }
            Button("取消", role: .cancel) {}
        } message: {
            Text(menuTitle)
        }
        .sheet(isPresented: $showSettings) {
            if let id = channelSettingsTarget {
                ChannelSettingsView(targetId: id)
                    .environmentObject(store)
            }
        }
    }

    @State private var channelSettingsTarget: UUID?

    private var menuTitle: String {
        let name = store.activeTarget?.name ?? ""
        let channel = store.activeChannel?.title ?? ""
        return "\(name) · \(channel) · \(AppInfo.versionLabel)"
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
        } catch (e) {}
      }

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
        view.backgroundColor = UIColor(red: 0.055, green: 0.055, blue: 0.075, alpha: 1)
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
