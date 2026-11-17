import SwiftUI
import AppKit
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
    @State private var pendingDelete: UUID?

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
                                            pendingDelete = target.id
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
        .confirmationDialog(
            "删除这个软件？对应的通道地址会一起删除，不可恢复。",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let id = pendingDelete { store.delete(id) }
                pendingDelete = nil
            }
            Button("取消", role: .cancel) { pendingDelete = nil }
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
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
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
        .padding(.top, 12)
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
                VStack(spacing: 0) {
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
                                    .textFieldStyle(.plain)
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
            }
            .navigationTitle("软件")
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
        .frame(minWidth: 420, minHeight: 480)
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
                .padding(.top, 12)
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
                                    .textFieldStyle(.plain)
                                    .autocorrectionDisabled()
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
        .frame(minWidth: 440, minHeight: 460)
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
    @State private var channelSettingsTarget: UUID?

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

            // 顶部：网络状态胶囊本身就是菜单入口
            Button {
                showMenu = true
            } label: {
                LatencyBadge(latency: store.latency, connected: true, showsMenuHint: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .confirmationDialog("DSH Desktop", isPresented: $showMenu, titleVisibility: .visible) {
            Button("重新加载") {
                failure = nil
                reloadToken += 1
            }

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
            if let url { Button("在 Safari 打开") { NSWorkspace.shared.open(url) } }
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
                Button("在 Safari 打开") { NSWorkspace.shared.open(url) }.buttonStyle(.bordered)
            }
            .font(.system(size: 14))
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - WebView 壳（macOS）

struct WebContainer: NSViewRepresentable {
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

    /// 浮动菜单定位兜底。
    ///
    /// DSH 的菜单用 CSS Anchor Positioning（anchor-name / position-anchor）
    /// 决定弹出位置。这个特性要 Safari 26（macOS 26）才支持；更早的 WKWebView
    /// 直接忽略这两个属性，菜单位置算不出来，就落在容器的左上角——
    /// 表现就是「点模型选择，弹层跑到左上角」。
    ///
    /// 窄屏（iPhone）走的是另一条用 JS 算坐标的路径，所以手机上正常。
    ///
    /// 这里做兜底：只在「菜单卡在左上角」或「浏览器不支持 anchor 定位」时才介入，
    /// 按触发按钮的位置把菜单摆到它上方或下方，并做视口内收敛。
    static let anchorFixJS = #"""
    (function () {
      if (window.__dshmAnchorFix) return;
      window.__dshmAnchorFix = true;

      var lastTrigger = null;

      function rememberTrigger(e) {
        var t = e.target;
        if (!t || !t.closest) return;
        var el = t.closest('[aria-haspopup],[role="button"],button');
        if (el) lastTrigger = el;
      }
      document.addEventListener('pointerdown', rememberTrigger, true);
      document.addEventListener('click', rememberTrigger, true);

      function isVisible(el) {
        var r = el.getBoundingClientRect();
        return r.width > 4 && r.height > 4;
      }

      function supportsAnchor() {
        try {
          return !!(window.CSS && CSS.supports && CSS.supports('anchor-name: --a'));
        } catch (e) { return false; }
      }

      function findTrigger(menu) {
        // 1) 通过 aria-controls 反查（DSH 会给触发按钮加 aria-controls=菜单id）
        if (menu.id) {
          var byControls = document.querySelector('[aria-controls~="' + menu.id + '"]');
          if (byControls) return byControls;
        }
        // 2) 当前展开的按钮
        var open = document.querySelectorAll('[aria-haspopup][aria-expanded="true"]');
        if (open.length) return open[open.length - 1];
        // 3) 最近一次点击的元素
        return lastTrigger;
      }

      function place(menu) {
        if (!isVisible(menu)) return;
        var mr = menu.getBoundingClientRect();
        var stuck = mr.left < 4 && mr.top < 4;
        if (!stuck && supportsAnchor()) return;   // 浏览器本来就能摆对，不干预

        var trig = findTrigger(menu);
        if (!trig) return;
        var tr = trig.getBoundingClientRect();
        if (tr.width < 1 && tr.height < 1) return;

        var vw = window.innerWidth || 360;
        var vh = window.innerHeight || 640;
        var w = mr.width;
        var h = mr.height;

        var side = menu.getAttribute('data-anchor-side');
        if (!side) side = (tr.top + tr.height / 2 > vh * 0.6) ? 'top' : 'bottom';
        var align = menu.getAttribute('data-anchor-align') || 'end';

        var left = (align === 'start') ? tr.left : (tr.right - w);
        var top = (side === 'top') ? (tr.top - h - 6) : (tr.bottom + 6);

        left = Math.max(8, Math.min(left, vw - w - 8));
        top = Math.max(8, Math.min(top, vh - h - 8));

        menu.style.position = 'fixed';
        menu.style.left = left + 'px';
        menu.style.top = top + 'px';
        menu.style.right = 'auto';
        menu.style.bottom = 'auto';
        menu.style.margin = '0';
      }

      function scan() {
        var menus = document.querySelectorAll('[role="menu"],[data-anchor-side]');
        for (var i = 0; i < menus.length; i++) place(menus[i]);
      }

      var queued = false;
      function schedule() {
        if (queued) return;
        queued = true;
        requestAnimationFrame(function () { queued = false; scan(); });
      }

      try {
        new MutationObserver(schedule).observe(document.documentElement, {
          childList: true, subtree: true,
          attributes: true, attributeFilter: ['style', 'class', 'data-anchor-side', 'aria-expanded']
        });
      } catch (e) {}
      setInterval(scan, 500);
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

      // 页面上出现「按住说话」面板时，把面板尺寸贴合到输入框：
      // DSH 自带的 composer 在窄窗口下会出现多余留白，这里用联合矩形收窄。
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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // 让页面里的音频/视频不需要额外点击就能播放（自动朗读依赖这一条）
        config.mediaTypesRequiringUserActionForPlayback = []

        let controller = config.userContentController
        controller.add(context.coordinator, name: "dshmSave")
        controller.add(context.coordinator, name: "dshmPing")
        controller.addUserScript(WKUserScript(
            source: Self.bootstrapJS,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        ))
        // 菜单定位兜底：要等 body 存在，所以放在 documentEnd；内部还有 MutationObserver 持续生效
        controller.addUserScript(WKUserScript(
            source: Self.anchorFixJS,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.uiDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = false
        // macOS 的 WKWebView 没有 isOpaque / backgroundColor，
        // 用私有的 drawsBackground 关掉，避免页面未加载时闪白底。
        view.setValue(false, forKey: "drawsBackground")
        context.coordinator.load(url, token: reloadToken, in: view)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(url, token: reloadToken, in: view)
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.stopPinging()
        view.configuration.userContentController.removeScriptMessageHandler(forName: "dshmSave")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "dshmPing")
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        private let parent: WebContainer
        private var loadedKey = ""
        /// 本次加载页面的 host，用于媒体采集授权白名单（换页要跟着换）。
        private var trustedHost = ""
        private var pingTimer: Timer?

        init(_ parent: WebContainer) {
            self.parent = parent
        }

        func load(_ url: URL, token: Int, in view: WKWebView) {
            let key = "\(url.absoluteString)#\(token)"
            guard key != loadedKey else { return }
            loadedKey = key
            trustedHost = (url.host ?? "").lowercased()
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            view.load(request)
        }

        // MARK: - 麦克风 / 摄像头

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
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
            if ns.code == -1202 || ns.code == -1200 || ns.code == -9807 {
                text += "\n\n这台电脑用的是自签证书。App 已经放行了私有地址的自签证书，"
                text += "还报错的话说明请求没走到 App 的放行逻辑——试试在 Safari 里打开同一地址。"
            }
            parent.failure = text
        }

        /// 接受私有地址的自签证书。
        /// 只对私有网段和 tailnet 域名放行，公网域名照常严格校验。
        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            let host = challenge.protectionSpace.host
            guard Self.allowsSelfSigned(host) else {
                completionHandler(.performDefaultHandling, nil)
                return
            }

            completionHandler(.useCredential, URLCredential(trust: trust))
        }

        private static func allowsSelfSigned(_ host: String) -> Bool {
            if host == "localhost" || host == "::1" { return true }
            if host.hasSuffix(".ts.net") { return true }

            let parts = host.split(separator: ".")
            guard parts.count == 4,
                  let a = Int(parts[0]),
                  let b = Int(parts[1]) else { return false }

            if a == 127 { return true }
            if a == 192 && b == 168 { return true }
            if a == 10 { return true }
            if a == 172 && (16...31).contains(b) { return true }
            return false
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let target = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // 表单提交（POST）一律放行。
            // 对 targetFrame == nil 的导航重新 load() 会丢掉 body，
            // 配对页的 PIN 表单就是这样被吞掉的。
            let httpMethod = (navigationAction.request.httpMethod ?? "GET").uppercased()
            if httpMethod == "POST" {
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
            NSWorkspace.shared.open(target)
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

        // MARK: 文件选择

        /// macOS 上 WKOpenPanelParameters 从 10.12 就有。
        /// 按 accept 收窄 NSOpenPanel 的类型；读不到 accept 就不过滤。
        func webView(_ webView: WKWebView,
                     runOpenPanelWith parameters: WKOpenPanelParameters,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = false
            panel.canChooseFiles = true
            panel.canCreateDirectories = false

            let types = Self.acceptedContentTypes(parameters)
            if !types.isEmpty {
                panel.allowedContentTypes = types
            }

            let handler: (NSApplication.ModalResponse) -> Void = { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
            if let window = webView.window {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                handler(panel.runModal())
            }
        }

        /// acceptMIMETypes 不在公开头文件里（WKOpenPanelParametersPrivate.h 的
        /// `_acceptedMIMETypes`），运行时探一下再 KVC；读不到返回空 = 不过滤。
        private static func acceptedContentTypes(_ parameters: WKOpenPanelParameters) -> [UTType] {
            let object = parameters as NSObject
            for key in ["acceptMIMETypes", "_acceptedMIMETypes"] {
                guard object.responds(to: NSSelectorFromString(key)) else { continue }
                guard let list = object.value(forKey: key) as? [String], !list.isEmpty else { continue }
                var types: [UTType] = []
                for mime in list {
                    if let type = UTType(mimeType: mime) {
                        types.append(type)
                    } else if mime.hasSuffix("/*"),
                              let type = UTType(tag: String(mime.dropLast(2)), tagClass: .filenameExtension, conformingTo: nil) {
                        types.append(type)
                    }
                }
                if !types.isEmpty { return types }
            }
            return []
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
            guard let bytes = Data(base64Encoded: data, options: .ignoreUnknownCharacters) else { return }

            // macOS 上用「存储为」对话框，替代 iOS 的分享面板。
            let panel = NSSavePanel()
            panel.nameFieldStringValue = name
            panel.canCreateDirectories = true
            let handler: (NSApplication.ModalResponse) -> Void = { response in
                guard response == .OK, let dest = panel.url else { return }
                try? bytes.write(to: dest)
            }
            if let window = NSApp.keyWindow {
                panel.beginSheetModal(for: window, completionHandler: handler)
            } else {
                handler(panel.runModal())
            }
        }

        // MARK: 原生对话框

        private func present(_ alert: NSAlert,
                             in webView: WKWebView?,
                             then completion: @escaping (NSApplication.ModalResponse) -> Void) {
            if let window = webView?.window ?? NSApp.keyWindow {
                alert.beginSheetModal(for: window, completionHandler: completion)
            } else {
                completion(alert.runModal())
            }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "好")
            present(alert, in: webView) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            present(alert, in: webView) { response in
                completionHandler(response == .alertFirstButtonReturn)
            }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            let alert = NSAlert()
            alert.messageText = prompt
            let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
            field.stringValue = defaultText ?? ""
            alert.accessoryView = field
            alert.addButton(withTitle: "确定")
            alert.addButton(withTitle: "取消")
            present(alert, in: webView) { response in
                completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
            }
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            loadedKey = ""
            parent.failure = nil
            webView.reload()
        }
    }
}
