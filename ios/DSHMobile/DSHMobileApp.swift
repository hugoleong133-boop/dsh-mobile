import SwiftUI

/// 应用入口。DSH Mobile 是个 WKWebView 壳：
/// 真正的程序跑在电脑上，这里只负责「选软件 → 选通道 → 显示延迟」。
@main
struct DSHMobileApp: App {
    @StateObject private var store = EndpointStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - 通道

enum DSHChannel: String, CaseIterable, Identifiable, Codable {
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

    var symbol: String {
        switch self {
        case .lan: return "wifi"
        case .funnel: return "globe.asia.australia"
        case .tailnet: return "network"
        }
    }
}

// MARK: - 软件（一个软件 = 一组通道地址）

struct AppTarget: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    /// channel.rawValue -> 地址字符串
    var channels: [String: String]
    var accent: Int

    init(id: UUID = UUID(), name: String, channels: [String: String] = [:], accent: Int = 0) {
        self.id = id
        self.name = name
        self.channels = channels
        self.accent = accent
    }

    var configuredCount: Int {
        channels.values.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    var initial: String {
        String(name.trimmingCharacters(in: .whitespaces).prefix(1)).uppercased()
    }
}

// MARK: - 配色

enum Palette {
    static let accents: [Color] = [
        Color(red: 0.36, green: 0.47, blue: 1.00),   // 蓝
        Color(red: 0.28, green: 0.78, blue: 0.68),   // 青绿
        Color(red: 0.98, green: 0.60, blue: 0.30),   // 橙
        Color(red: 0.93, green: 0.42, blue: 0.62),   // 粉
        Color(red: 0.95, green: 0.78, blue: 0.30),   // 黄
        Color(red: 0.62, green: 0.46, blue: 0.96),   // 靛
    ]

    static func accent(_ index: Int) -> Color {
        accents[((index % accents.count) + accents.count) % accents.count]
    }

    /// 比纯黑亮一档，卡片才有层次
    static let background = LinearGradient(
        colors: [
            Color(red: 0.105, green: 0.105, blue: 0.135),
            Color(red: 0.055, green: 0.055, blue: 0.075),
        ],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardFill = Color.white.opacity(0.10)
    static let cardStroke = Color.white.opacity(0.14)
    static let cardFillDim = Color.white.opacity(0.045)
    static let cardStrokeDim = Color.white.opacity(0.09)
}

// MARK: - 存储

final class EndpointStore: ObservableObject {
    @Published private(set) var targets: [AppTarget] = []
    @Published private(set) var activeTargetId: UUID?
    @Published private(set) var activeChannel: DSHChannel?
    @Published var latency: Int?

    private static let targetsKey = "dshm.targets.v2"
    private static let legacyChannelPrefix = "dshm.ch.channel."
    private static let legacyMultiKey = "dshm.endpoints"

    init() {
        load()
    }

    // MARK: 计算属性

    var activeTarget: AppTarget? {
        guard let activeTargetId else { return nil }
        return targets.first { $0.id == activeTargetId }
    }

    var activeURL: URL? {
        guard let activeTargetId, let activeChannel else { return nil }
        return url(in: activeTargetId, channel: activeChannel)
    }

    func target(_ id: UUID) -> AppTarget? {
        targets.first { $0.id == id }
    }

    func url(in targetId: UUID, channel: DSHChannel) -> URL? {
        guard let target = target(targetId),
              let raw = target.channels[channel.rawValue] else { return nil }
        return Self.parse(raw)
    }

    // MARK: 软件增删改

    @discardableResult
    func addTarget(name: String) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = AppTarget(
            name: trimmed.isEmpty ? "未命名" : trimmed,
            accent: targets.count
        )
        targets.append(target)
        persist()
        return target.id
    }

    func rename(_ id: UUID, to name: String) {
        guard let index = targets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        targets[index].name = trimmed.isEmpty ? "未命名" : trimmed
        persist()
    }

    func delete(_ id: UUID) {
        targets.removeAll { $0.id == id }
        if activeTargetId == id { disconnect() }
        persist()
    }

    // MARK: 地址

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

    /// 保存即持久化 —— 这就是「自动锁定」
    func save(_ raw: String, in targetId: UUID, channel: DSHChannel) throws {
        guard let index = targets.firstIndex(where: { $0.id == targetId }) else { return }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            targets[index].channels.removeValue(forKey: channel.rawValue)
        } else {
            guard let url = Self.parse(trimmed) else { throw StoreError.malformed }
            targets[index].channels[channel.rawValue] = url.absoluteString
        }
        persist()
    }

    // MARK: 连接

    func connect(targetId: UUID, channel: DSHChannel) {
        guard url(in: targetId, channel: channel) != nil else { return }
        activeTargetId = targetId
        activeChannel = channel
        latency = nil
    }

    func disconnect() {
        activeTargetId = nil
        activeChannel = nil
        latency = nil
    }

    // MARK: 持久化

    private func persist() {
        if let data = try? JSONEncoder().encode(targets) {
            UserDefaults.standard.set(data, forKey: Self.targetsKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.targetsKey),
           let decoded = try? JSONDecoder().decode([AppTarget].self, from: data) {
            targets = decoded
            return
        }

        // 从旧版本迁移成一个「DSH」条目
        var legacy: [String: String] = [:]
        for channel in DSHChannel.allCases {
            if let raw = UserDefaults.standard.string(forKey: Self.legacyChannelPrefix + channel.rawValue),
               !raw.isEmpty {
                legacy[channel.rawValue] = raw
            }
        }
        if legacy.isEmpty, let multi = UserDefaults.standard.string(forKey: Self.legacyMultiKey) {
            let parts = multi.split(whereSeparator: { $0 == "\n" || $0 == "," })
            for (index, part) in parts.enumerated() where index < DSHChannel.allCases.count {
                legacy[DSHChannel.allCases[index].rawValue] = String(part)
            }
        }
        if !legacy.isEmpty {
            targets = [AppTarget(name: "DSH", channels: legacy, accent: 0)]
            persist()
        }
    }

    enum StoreError: LocalizedError {
        case malformed

        var errorDescription: String? {
            "地址格式不对，形如 192.168.1.124:8765/?k=338599"
        }
    }
}
