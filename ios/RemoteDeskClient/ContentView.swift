import SwiftUI

/// 主界面：连接表单 + 远程画面。
struct ContentView: View {

    @StateObject private var session = Session()
    @State private var host = "100.126.113.122"
    @State private var port = "9527"
    @State private var password = ""

    var body: some View {
        VStack(spacing: 0) {
            if session.connected {
                RemoteView(session: session)
                    .overlay(alignment: .top) {
                        statusBar
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button("Ctrl+Alt+Del") { session.sendCtrlAltDel() }
                            Button("请求关键帧") { session.requestKeyFrame() }
                            Spacer()
                            Text("\(session.fps, specifier: "%.1f") fps")
                                .font(.caption.monospacedDigit())
                            Button("断开") { session.disconnect() }
                        }
                    }
            } else {
                connectForm
            }
        }
        .navigationTitle("RemoteDesk")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var connectForm: some View {
        Form {
            Section("被控端") {
                TextField("主机地址", text: $host)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                TextField("端口", text: $port)
                    .keyboardType(.numberPad)
                SecureField("连接密码", text: $password)
            }
            Section {
                Button("连接") {
                    session.connect(host: host, port: UInt16(port) ?? 9527, password: password) { err in
                        session.statusText = err
                    }
                }
                .disabled(host.isEmpty || password.isEmpty)
            }
            Text(session.statusText)
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }

    private var statusBar: some View {
        HStack {
            Text(session.statusText)
                .font(.caption)
                .foregroundColor(.white)
                .padding(6)
                .background(Color.black.opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Spacer()
        }
        .padding(8)
    }
}
