import SwiftUI

/// Xcode App 入口。建 App 时把本目录所有 .swift 文件拖进工程即可。
@main
struct RemoteDeskApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationView {
                ContentView()
            }
        }
    }
}
