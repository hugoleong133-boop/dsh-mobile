import SwiftUI

/// 应用入口。DSH Mobile 只是个 WKWebView 壳：
/// 真正的 agent 跑在电脑上，这里负责选通道、记住地址、显示延迟。
@main
struct DSHMobileApp: App {
    @StateObject private var store = EndpointStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(nil)
        }
    }
}

/// 三条接入通道。各自存一个地址，互不影响。
enum DSHChannel: String, CaseIterable, Identifiable {
    case lan
    case funnel
    case tailnet

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lan: return "局域网"
        case .funnel: return "Funnel"
        case .tailnet: return "tailnet"
        }
    }

    var caption: String {
        switch self {
        case .lan: return "同一 WiFi 下最快"
        case .funnel: return "公网 HTTPS，不需要 Tailscale"
        case .tailnet: return "需要 Tailscale 在线"
        }
    }

    var placeholder: String {
        switch self {
        case .lan: return "192.168.1.124:8765/?k=338599"
        case .funnel: return "https://xxx.ts.net/?k=338599"
        case .tailnet: return "http://xxx.ts.net:8765/?k=338599"
        }
    }
}

/// 通道地址持久化 + 当前连接状态。
/// 地址存进 UserDefaults，保存后即「锁定」，下次启动直接可用，不需要重新输入。
final class EndpointStore: ObservableObject {
    @Published private(set) var endpoints: [DSHChannel: URL] = [:]
    @Published private(set) var active: DSHChannel?
    @Published var latency: Int?

    private static let keyPrefix = "dshm.ch.channel."
    private static let legacyKey = "dshm.endpoints"

    init() {
        load()
    }

    var activeURL: URL? {
        guard let active else { return nil }
        return endpoints[active]
    }

    func url(for channel: DSHChannel) -> URL? {
        endpoints[channel]
    }

    func isConfigured(_ channel: DSHChannel) -> Bool {
        endpoints[channel] != nil
    }

    // MARK: 存取

    private func load() {
        let defaults = UserDefaults.standard
        for channel in DSHChannel.allCases {
            if let raw = defaults.string(forKey: Self.keyPrefix + channel.rawValue),
               let url = Self.parse(raw) {
                endpoints[channel] = url
            }
        }

        // 从旧版「一个输入框填多行」迁移：按顺序填进三个通道
        if endpoints.isEmpty,
           let legacy = defaults.string(forKey: Self.legacyKey) {
            let parts = legacy.split(whereSeparator: { $0 == "\n" || $0 == "," })
            for (index, part) in parts.enumerated() where index < DSHChannel.allCases.count {
                let channel = DSHChannel.allCases[index]
                if let url = Self.parse(String(part)) {
                    endpoints[channel] = url
                    defaults.set(url.absoluteString, forKey: Self.keyPrefix + channel.rawValue)
                }
            }
            defaults.removeObject(forKey: Self.legacyKey)
        }
    }

    /// 只接受 http(s)，缺协议头时补 http://
    static func parse(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let lower = text.lowercased()
        if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text), components.host != nil else { return nil }
        if components.path.isEmpty { components.path = "/" }
        return components.url
    }

    /// 保存后立刻持久化 —— 这就是「自动锁定」
    func save(_ raw: String, for channel: DSHChannel) throws {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            clear(channel)
            return
        }
        guard let url = Self.parse(trimmed) else { throw StoreError.malformed }
        endpoints[channel] = url
        UserDefaults.standard.set(url.absoluteString, forKey: Self.keyPrefix + channel.rawValue)
    }

    func clear(_ channel: DSHChannel) {
        endpoints.removeValue(forKey: channel)
        UserDefaults.standard.removeObject(forKey: Self.keyPrefix + channel.rawValue)
        if active == channel {
            active = nil
            latency = nil
        }
    }

    // MARK: 连接

    func connect(_ channel: DSHChannel) {
        guard endpoints[channel] != nil else { return }
        active = channel
        latency = nil
    }

    func disconnect() {
        active = nil
        latency = nil
    }

    enum StoreError: LocalizedError {
        case malformed

        var errorDescription: String? {
            "地址格式不对，形如 192.168.1.124:8765/?k=338599"
        }
    }
}
