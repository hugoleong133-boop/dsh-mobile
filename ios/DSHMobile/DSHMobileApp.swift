import SwiftUI

/// DSH Mobile —— 把桌面 DSH 的 Web 会话包进一个原生壳。
///
/// 它不实现任何业务逻辑：真正的 agent 跑在电脑上，这个 App 只是
/// WKWebView + 一个记住配对地址的壳。配对地址（含 PIN）由 dsh-mobile 的
/// start.ps1 打印，形如 http://192.168.1.124:8765/?k=123456。
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

/// 配对信息持久化。只存 URL；PIN 用一次就换成服务端下发的 HttpOnly cookie。
final class EndpointStore: ObservableObject {
    @Published var endpoint: URL?
    @Published var pairInput: String = ""

    private static let key = "dshm.endpoint"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.key), let url = URL(string: raw) {
            endpoint = url
        }
    }

    /// 接受 `192.168.1.124:8765/?k=123456`、`http://...`、或带 PIN 的完整链接。
    func pair(from raw: String) throws {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw PairError.empty }
        if !text.lowercased().hasPrefix("http://") && !text.lowercased().hasPrefix("https://") {
            text = "http://" + text
        }
        guard var components = URLComponents(string: text), components.host != nil else {
            throw PairError.malformed
        }
        if components.path.isEmpty { components.path = "/" }
        guard let url = components.url else { throw PairError.malformed }
        UserDefaults.standard.set(url.absoluteString, forKey: Self.key)
        endpoint = url
        pairInput = ""
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.key)
        endpoint = nil
    }

    enum PairError: LocalizedError {
        case empty
        case malformed

        var errorDescription: String? {
            switch self {
            case .empty: return "先填电脑上 start.ps1 打印的地址"
            case .malformed: return "地址格式不对，形如 192.168.1.124:8765/?k=123456"
            }
        }
    }
}
