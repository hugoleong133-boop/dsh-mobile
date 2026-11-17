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

// MARK: - 寤惰繜鑳跺泭

struct LatencyBadge: View {
    let latency: Int?
    var connected: Bool = false
    /// 浼氳瘽椤垫妸鑿滃崟骞惰繘杩欎釜鑳跺泭锛岀敤涓€涓皬鎻愮ず鐐硅〃鏄庡彲鐐?    var showsMenuHint: Bool = false

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
        if !connected { return "鏈繛鎺? }
        guard let latency else { return "杩炴帴涓€? }
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

// MARK: - 棣栭〉锛氶€夎蒋浠?
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
                                            Label("閲嶅懡鍚?, systemImage: "pencil")
                                        }
                                        Button(role: .destructive) {
                                            pendingDelete = target.id
                                        } label: {
                                            Label("鍒犻櫎", systemImage: "trash")
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
            "閲嶅懡鍚?,
            isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )
        ) {
            TextField("鍚嶇О", text: $renameText)
            Button("鍙栨秷", role: .cancel) { renameTarget = nil }
            Button("淇濆瓨") {
                if let id = renameTarget { store.rename(id, to: renameText) }
                renameTarget = nil
            }
        }
        .confirmationDialog(
            "鍒犻櫎杩欎釜杞欢锛熷搴旂殑閫氶亾鍦板潃浼氫竴璧峰垹闄わ紝涓嶅彲鎭㈠銆?,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("鍒犻櫎", role: .destructive) {
                if let id = pendingDelete { store.delete(id) }
                pendingDelete = nil
            }
            Button("鍙栨秷", role: .cancel) { pendingDelete = nil }
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
            Text("杩樻病鏈夋坊鍔犺蒋浠?)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
            Text("鐐瑰乏涓婅 + 娣诲姞涓€涓?)
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
                Text(target.configuredCount > 0 ? "\(target.configuredCount) 鏉￠€氶亾宸查厤缃? : "鏈厤缃湴鍧€")
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

// MARK: - 杞欢绠＄悊

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
                                        Text("\(target.configuredCount) 閫氶亾")
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
                                TextField("鏂板杞欢鍚嶇О", text: $newName)
                                    .textFieldStyle(.plain)
                                    .foregroundStyle(.white)
                                Button("娣诲姞") {
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
            .navigationTitle("杞欢")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("瀹屾垚") { dismiss() }
                }
            }
            .alert(
                "閲嶅懡鍚?,
                isPresented: Binding(
                    get: { renameTarget != nil },
                    set: { if !$0 { renameTarget = nil } }
                )
            ) {
                TextField("鍚嶇О", text: $renameText)
                Button("鍙栨秷", role: .cancel) { renameTarget = nil }
                Button("淇濆瓨") {
                    if let id = renameTarget { store.rename(id, to: renameText) }
                    renameTarget = nil
                }
            }
        }
        .frame(minWidth: 420, minHeight: 480)
    }
}

// MARK: - 閫氶亾閫夋嫨

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
        .navigationTitle(target?.name ?? "閫氶亾")
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
                    Text(url?.absoluteString ?? "鏈缃?)
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

// MARK: - 閫氶亾璁剧疆

struct ChannelSettingsView: View {
    let targetId: UUID
    @EnvironmentObject private var store: EndpointStore
    @Environment(\.dismiss) private var dismiss

    @State private var drafts: [DSHChannel: String] = [:]
    @State private var error: String?

    private var targetName: String {
        store.target(targetId)?.name ?? "閫氶亾"
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
                                        Button("娓呴櫎") { drafts[channel] = "" }
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
                    Button("鍙栨秷") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("淇濆瓨") { save() }
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

// MARK: - 浼氳瘽

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

            // 椤堕儴锛氱綉缁滅姸鎬佽兌鍥婃湰韬氨鏄彍鍗曞叆鍙?            Button {
                showMenu = true
            } label: {
                LatencyBadge(latency: store.latency, connected: true, showsMenuHint: true)
            }
            .buttonStyle(.plain)
            .padding(.top, 10)
        }
        .confirmationDialog("DSH Desktop", isPresented: $showMenu, titleVisibility: .visible) {
            Button("閲嶆柊鍔犺浇") {
                failure = nil
                reloadToken += 1
            }

            if let first = alternates.first {
                Button("鍒囨崲鍒?\(first.title)") { switchTo(first) }
            }
            if alternates.count > 1 {
                Button("鍒囨崲鍒?\(alternates[1].title)") { switchTo(alternates[1]) }
            }

            Button("鍒囨崲杞欢") { store.disconnect() }
            if let id = store.activeTargetId {
                Button("閫氶亾璁剧疆") { channelSettingsTarget = id; showSettings = true }
            }
            if let url { Button("鍦?Safari 鎵撳紑") { NSWorkspace.shared.open(url) } }
            Button("鍙栨秷", role: .cancel) {}
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

    /// 褰撳墠杞欢涓嬨€侀櫎褰撳墠閫氶亾澶栥€佸凡缁忛厤濂藉湴鍧€鐨勯€氶亾锛堟渶澶氫袱鏉★級
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
        return "\(name) 路 \(channel) 路 \(AppInfo.versionLabel)"
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
                Text("鎵撲笉寮€杩欎釜鍦板潃").font(.system(size: 17, weight: .semibold))
            }
            Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
            Text(url.absoluteString)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack(spacing: 10) {
                Button("閲嶈瘯", action: onRetry).buttonStyle(.borderedProminent)
                Button("鍒囨崲閫氶亾", action: onSwitch).buttonStyle(.bordered)
                Button("鍦?Safari 鎵撳紑") { NSWorkspace.shared.open(url) }.buttonStyle(.bordered)
            }
            .font(.system(size: 14))
        }
        .padding(18)
        .frame(maxWidth: 440)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

// MARK: - WebView 澹筹紙macOS锛?
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

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
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
        // macOS 涓?WKWebView 娌℃湁 isOpaque / backgroundColor锛?        // 鍙兘閫氳繃绉佹湁鐨?drawsBackground 鍏虫帀锛岄伩鍏嶉〉闈㈡湭鍔犺浇鏃堕棯鐧藉簳銆?        view.setValue(false, forKey: "drawsBackground")
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
        /// 鏈鍔犺浇椤甸潰鐨?host锛岀敤浜庡獟浣撻噰闆嗘巿鏉冪櫧鍚嶅崟锛堟崲椤佃璺熺潃鎹級銆?        private var trustedHost = ""
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

        // MARK: - 楹﹀厠椋?/ 鎽勫儚澶?
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

            var text = "\(ns.localizedDescription)锛圽(ns.domain) \(ns.code)锛?
            if ns.code == -1022 || ns.code == -1004 || ns.code == -1009 || ns.code == -1001 {
                text += "\n\n妫€鏌ョ數鑴戜笂 8765 鏄惁鍦ㄨ窇锛屼互鍙婅繖涓綉缁滆兘涓嶈兘鍒拌鍦板潃銆?
            }
            if ns.code == -1202 || ns.code == -1200 || ns.code == -9807 {
                text += "\n\n杩欏彴鐢佃剳鐢ㄧ殑鏄嚜绛捐瘉涔︺€侫pp 宸茬粡鏀捐浜嗙鏈夊湴鍧€鐨勮嚜绛捐瘉涔︼紝"
                text += "杩樻姤閿欑殑璇濊鏄庤姹傛病璧板埌 App 鐨勬斁琛岄€昏緫鈥斺€旇瘯璇曞湪 Safari 閲屾墦寮€鍚屼竴鍦板潃銆?
            }
            parent.failure = text
        }

        /// 鎺ュ彈绉佹湁鍦板潃鐨勮嚜绛捐瘉涔︺€?        /// 鍙绉佹湁缃戞鍜?tailnet 鍩熷悕鏀捐锛屽叕缃戝煙鍚嶇収甯镐弗鏍兼牎楠屻€?        func webView(_ webView: WKWebView,
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

            // 琛ㄥ崟鎻愪氦锛圥OST锛変竴寰嬫斁琛屻€?            // 瀵?targetFrame == nil 鐨勫鑸噸鏂?load() 浼氫涪鎺?body锛?            // 閰嶅椤电殑 PIN 琛ㄥ崟灏辨槸杩欐牱琚悶鎺夌殑銆?            let httpMethod = (navigationAction.request.httpMethod ?? "GET").uppercased()
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

        // MARK: 鏂囦欢閫夋嫨

        /// macOS 涓?WKOpenPanelParameters 浠?10.12 灏辨湁锛屼笉闇€瑕佸彲鐢ㄦ€ф爣娉ㄣ€?        /// 鍙寜 accept 鏀剁獎 NSOpenPanel 鐨勭被鍨嬶紱鐩稿唽/鐩告満鍦?macOS 涓婃病鏈夊搴旀蹇碉紝
        /// 鎻愮ず銆岀収鐗囧浘搴撱€嶅湪杩欓噷灏辨槸銆屽浘鐗囥€嶆枃浠剁被鍨嬨€?        func webView(_ webView: WKWebView,
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

        /// acceptMIMETypes 涓嶅湪鍏紑澶存枃浠堕噷锛圵KOpenPanelParametersPrivate.h 閲岀殑
        /// `_acceptedMIMETypes`锛夛紝杩愯鏃舵帰涓€涓嬪啀 KVC锛涜涓嶅埌灏辫繑鍥炵┖ = 涓嶈繃婊ゃ€?        private static func acceptedContentTypes(_ parameters: WKOpenPanelParameters) -> [UTType] {
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

        // MARK: 娑堟伅妗?
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

            // macOS 涓婄敤銆屽瓨鍌ㄤ负銆嶅璇濇锛屾浛浠?iOS 鐨勫垎浜潰鏉裤€?            let panel = NSSavePanel()
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

        // MARK: 鍘熺敓瀵硅瘽妗?
        private func present(_ alert: NSAlert, in webView: WKWebView?, then completion: @escaping (NSApplication.ModalResponse) -> Void) {
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
            alert.addButton(withTitle: "濂?)
            present(alert, in: webView) { _ in completionHandler() }
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            let alert = NSAlert()
            alert.messageText = message
            alert.addButton(withTitle: "纭畾")
            alert.addButton(withTitle: "鍙栨秷")
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
            alert.addButton(withTitle: "纭畾")
            alert.addButton(withTitle: "鍙栨秷")
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
