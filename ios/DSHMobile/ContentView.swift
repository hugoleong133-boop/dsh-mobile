import SwiftUI
import UIKit
import WebKit
import UniformTypeIdentifiers
import PhotosUI

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
    /// 会话页把菜单并进这个胶囊，用一个小提示点表明可点
    var showsMenuHint: Bool = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dotColor).frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
            if showsMenuHint {
                Image(systemName: "ellipsis")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary.opacity(0.65))
                    .padding(.leading, 1)
            }
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

            // 顶部：网络状态胶囊本身就是菜单入口，不再单独放按钮
            Button {
                showMenu = true
            } label: {
                LatencyBadge(latency: store.latency, connected: true, showsMenuHint: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .confirmationDialog("DSH Mobile", isPresented: $showMenu, titleVisibility: .visible) {
            Button("重新加载") {
                failure = nil
                reloadToken += 1
            }

            // 直接把另外两条已配置的通道列出来，一步切过去。
            // 早期的「下一个地址」在三通道模型里没有明确含义，这里换成显式目标。
            // 不用 ForEach：confirmationDialog 对动态按钮的支持在旧系统上不稳定。
            if let first = alternates.first {
                Button("切换到 \(first.title)") { switchTo(first) }
            }
            if alternates.count > 1 {
                Button("切换到 \(alternates[1].title)") { switchTo(alternates[1]) }
            }

            Button("切换软件") { store.disconnect() }
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

    /// 当前软件下、除当前通道外、已经配好地址的通道（最多两条）
    private var alternates: [DSHChannel] {
        guard let targetId = store.activeTargetId else { return [] }
        return DSHChannel.allCases.compactMap { channel in
            guard channel != store.activeChannel,
                  store.url(in: targetId, channel: channel) != nil else { return nil }
            return channel
        }
    }

    private func switchTo(_ channel: DSHChannel) {
        guard let targetId = store.activeTargetId else { return }
        failure = nil
        store.connect(targetId: targetId, channel: channel)
    }

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

/// 多选照片时按 provider 的原始顺序收集导出结果。
/// `loadDataRepresentation` 的回调并发到达，用锁而不是捕获 var 拼接。
private final class PhotoCollector {
    private let lock = NSLock()
    private var slots: [URL?]

    init(count: Int) {
        slots = Array(repeating: nil, count: count)
    }

    func set(_ url: URL?, at index: Int) {
        guard slots.indices.contains(index) else { return }
        lock.lock()
        slots[index] = url
        lock.unlock()
    }

    func urls() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return slots.compactMap { $0 }
    }
}

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

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler,
                             UIDocumentPickerDelegate, PHPickerViewControllerDelegate,
                             UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: WebContainer
        private var loadedKey = ""
        /// 本次加载页面的 host，用于媒体采集授权白名单（换页要跟着换）。
        private var trustedHost = ""
        private var openPanelCompletion: (([URL]?) -> Void)?
        private var pingTimer: Timer?

        init(_ parent: WebContainer) {
            self.parent = parent
        }

        func load(_ url: URL, token: Int, in view: WKWebView) {
            let key = "\(url.absoluteString)#\(token)"
            guard key != loadedKey else { return }
            loadedKey = key
            trustedHost = (url.host() ?? "").lowercased()
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            view.load(request)
        }

        // MARK: - 麦克风
        //
        // iOS 15+ 的 WKWebView 默认拒绝网页的 getUserMedia：必须由 app 在
        // WKUIDelegate 里逐个 origin 授权。只在「当前加载页面的 host」上放行，
        // 避免被重定向到别的站点后仍能开麦。
        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKMediaCaptureDecision) -> Void) {
            let host = origin.host.lowercased()
            let samePage = !trustedHost.isEmpty && host == trustedHost
            switch type {
            case .microphone, .cameraAndMicrophone:
                decisionHandler(samePage ? .grant : .deny)
            default:
                decisionHandler(.prompt)
            }
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

        // MARK: 文件 / 照片选择
        //
        // WebKit 只把页面的 accept 传到这里：WKOpenPanelParameters.acceptMIMETypes。
        // 旧实现写死 UIDocumentPickerViewController + 一组混合 UTI（.item/.image/…），
        // 等于无视 accept —— 页面写 accept="image/*" 也只会进「文件」，相册和相机
        // 从来没被调用过。现在按 accept 分支：图片请求先给「照片图库 / 拍照 / 选取文件」，
        // 其余仍走原文件选择器。

        @available(iOS 18.4, *)
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            openPanelCompletion = completionHandler
            let multiple = parameters.allowsMultipleSelection
            let accepted = Self.acceptedMIMETypes(parameters)
            let wantsImages = accepted.contains { type in
                let lower = type.lowercased()
                return lower == "image/*" || lower.hasPrefix("image/")
            }
            guard wantsImages, let host = topViewController() else {
                presentDocumentPicker(multiple: multiple)
                return
            }

            let sheet = UIAlertController(title: "添加照片", message: nil, preferredStyle: .actionSheet)
            // 从 actionSheet 的 action 里立刻 present 另一个控制器，iOS 上偶尔会静默失败
            // （旧 sheet 还在 dismiss 动画里）。统一让一帧。
            sheet.addAction(UIAlertAction(title: "照片图库", style: .default) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.presentPhotoLibrary(multiple: multiple)
                }
            })
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                sheet.addAction(UIAlertAction(title: "拍照", style: .default) { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        self?.presentCamera()
                    }
                })
            }
            sheet.addAction(UIAlertAction(title: "选取文件", style: .default) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                    self?.presentDocumentPicker(multiple: multiple)
                }
            })
            sheet.addAction(UIAlertAction(title: "取消", style: .cancel) { [weak self] _ in
                self?.finishOpenPanel(nil)
            })
            if let pop = sheet.popoverPresentationController {
                pop.sourceView = host.view
                pop.sourceRect = CGRect(x: host.view.bounds.midX, y: host.view.bounds.midY, width: 0, height: 0)
                pop.permittedArrowDirections = []
            }
            host.present(sheet, animated: true)
        }

        /// `acceptMIMETypes` 不在 iOS 18.4 的公开头文件里：公开的只有
        /// allowsMultipleSelection / allowsDirectories，MIME 列表在
        /// WKOpenPanelParametersPrivate.h，名字是 `_acceptedMIMETypes`。
        /// 运行时探一下再 KVC；读不到就返回空（等于退回文件选择器，不会崩）。
        private static func acceptedMIMETypes(_ parameters: WKOpenPanelParameters) -> [String] {
            let object = parameters as NSObject
            for key in ["acceptMIMETypes", "_acceptedMIMETypes"] {
                guard object.responds(to: NSSelectorFromString(key)) else { continue }
                if let list = object.value(forKey: key) as? [String], !list.isEmpty {
                    return list
                }
            }
            return []
        }

        private func presentDocumentPicker(multiple: Bool) {
            let picker = UIDocumentPickerViewController(
                forOpeningContentTypes: [.item, .image, .movie, .audio, .text, .pdf, .data],
                asCopy: true
            )
            picker.allowsMultipleSelection = multiple
            picker.delegate = self
            topViewController()?.present(picker, animated: true)
        }

        private func presentPhotoLibrary(multiple: Bool) {
            var config = PHPickerConfiguration()
            config.filter = .images
            // 0 = 不限制；单选的 input 只允许一张，和页面语义保持一致。
            config.selectionLimit = multiple ? 0 : 1
            config.preferredAssetRepresentationMode = .current
            let picker = PHPickerViewController(configuration: config)
            picker.delegate = self
            topViewController()?.present(picker, animated: true)
        }

        private func presentCamera() {
            guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                finishOpenPanel(nil)
                return
            }
            let picker = UIImagePickerController()
            picker.sourceType = .camera
            picker.cameraCaptureMode = .photo
            picker.delegate = self
            topViewController()?.present(picker, animated: true)
        }

        private func finishOpenPanel(_ urls: [URL]?) {
            let completion = openPanelCompletion
            openPanelCompletion = nil
            completion?(urls)
        }

        // MARK: PHPicker

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard !results.isEmpty else {
                finishOpenPanel(nil)
                return
            }
            exportPhotos(results)
        }

        /// PHPicker 交回的是 NSItemProvider，WebKit 只接受沙盒里可读的 URL，
        /// 所以统一导出成 JPEG 临时文件再回调（页面侧也就不必再处理 HEIC）。
        private func exportPhotos(_ results: [PHPickerResult]) {
            let group = DispatchGroup()
            let collector = PhotoCollector(count: results.count)

            for (index, result) in results.enumerated() {
                let provider = result.itemProvider
                guard let identifier = Self.imageTypeIdentifier(of: provider) else { continue }
                group.enter()
                provider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
                    defer { group.leave() }
                    guard let data, let image = UIImage(data: data) else { return }
                    collector.set(Self.writeJPEG(image, named: provider.suggestedName), at: index)
                }
            }

            group.notify(queue: .main) { [weak self] in
                let urls = collector.urls()
                self?.finishOpenPanel(urls.isEmpty ? nil : urls)
            }
        }

        private static func imageTypeIdentifier(of provider: NSItemProvider) -> String? {
            for identifier in provider.registeredTypeIdentifiers {
                guard let type = UTType(identifier), type.conforms(to: .image) else { continue }
                return identifier
            }
            return nil
        }

        private static func writeJPEG(_ image: UIImage, named suggested: String?) -> URL? {
            guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
            let raw = (suggested ?? "photo").trimmingCharacters(in: .whitespacesAndNewlines)
            let stem = raw.isEmpty ? "photo" : String(raw.prefix(48))
            let name = "\(stem)-\(UUID().uuidString.prefix(8)).jpg"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
            do {
                try data.write(to: url)
                return url
            } catch {
                return nil
            }
        }

        // MARK: 相机

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            picker.dismiss(animated: true)
            guard let image = info[.originalImage] as? UIImage,
                  let url = Self.writeJPEG(image, named: "camera") else {
                finishOpenPanel(nil)
                return
            }
            finishOpenPanel([url])
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
            finishOpenPanel(nil)
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
