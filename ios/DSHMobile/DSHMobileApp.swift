import SwiftUI

/// DSH Mobile —— 把桌面 DSH 的 Web 会话包进一个原生壳。
///
/// 它不实现任何业务逻辑：真正的 agent 跑在电脑上，这个 App 只是
/// WKWebView + 一个记住配对地址的壳。
///
/// 支持**多个地址按顺序自动选路**：同一个会话可以同时有局域网、tailnet、
/// Funnel 三个入口，在家走局域网最快，出门自动切到公网入口。
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

/// 配对信息持久化。地址是一组，会记住上次成功的那个。
final class EndpointStore: ObservableObject {
    @Published var endpoints: [URL] = []
    @Published var activeIndex: Int = 0
    @Published var pairInput: String = ""

    private static let listKey = "dshm.endpoints"
    private static let goodKey = "dshm.lastGoodIndex"
    private static let legacyKey = "dshm.endpoint"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.listKey),
           let urls = Self.parseList(raw), !urls.isEmpty {
            endpoints = urls
        } else if let legacy = UserDefaults.standard.string(forKey: Self.legacyKey),
                  let url = URL(string: legacy) {
            // 从只支持单地址的旧版迁移
            endpoints = [url]
            UserDefaults.standard.set(legacy, forKey: Self.listKey)
            UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        }

        let good = UserDefaults.standard.integer(forKey: Self.goodKey)
        if endpoints.indices.contains(good) {
            activeIndex = good
        }
    }

    var active: URL? {
        endpoints.indices.contains(activeIndex) ? endpoints[activeIndex] : nil
    }

    var hasFallback: Bool {
        activeIndex + 1 < endpoints.count
    }

    /// 按换行、逗号或空格分隔；缺协议头时补 http://
    static func parseList(_ raw: String) -> [URL]? {
        let parts = raw.split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == " " || $0 == "\r" })
        var urls: [URL] = []
        for part in parts {
            var text = String(part).trimmingCharacters(in: .whitespaces)
            if text.isEmpty { continue }
            let lower = text.lowercased()
            if !lower.hasPrefix("http://") && !lower.hasPrefix("https://") {
                text = "http://" + text
            }
            guard var components = URLComponents(string: text), components.host != nil else { continue }
            if components.path.isEmpty { components.path = "/" }
            guard let url = components.url else { continue }
            if !urls.contains(url) { urls.append(url) }
        }
        return urls.isEmpty ? nil : urls
    }

    func pair(from raw: String) throws {
        guard let urls = Self.parseList(raw) else { throw PairError.malformed }
        endpoints = urls
        activeIndex = 0
        pairInput = ""
        UserDefaults.standard.set(urls.map(\.absoluteString).joined(separator: "\n"), forKey: Self.listKey)
    }

    /// 换到下一个候选地址。已经是最后一个就返回 false。
    func advance() -> Bool {
        guard activeIndex + 1 < endpoints.count else { return false }
        activeIndex += 1
        return true
    }

    func restart() {
        activeIndex = 0
    }

    /// 记下当前地址可用，下次启动先试它
    func markGood() {
        UserDefaults.standard.set(activeIndex, forKey: Self.goodKey)
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.listKey)
        UserDefaults.standard.removeObject(forKey: Self.goodKey)
        UserDefaults.standard.removeObject(forKey: Self.legacyKey)
        endpoints = []
        activeIndex = 0
    }

    enum PairError: LocalizedError {
        case malformed

        var errorDescription: String? {
            "地址格式不对。多个地址用换行或逗号分开，形如 192.168.1.124:8765/?k=123456"
        }
    }
}
