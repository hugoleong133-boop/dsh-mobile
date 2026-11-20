import SwiftUI

/// 主界面：连接表单 + 远程画面。
struct ContentView: View {

    @StateObject private var session = Session()
    @State private var host = "100.126.113.122"
    @State private var port = "9527"
    @State private var password = ""
    @State private var showKeyboard = false
    @State private var keyboardText = ""
    @State private var toast = ""

    var body: some View {
        VStack(spacing: 0) {
            if session.connected {
                RemoteView(session: session)
                    .overlay(alignment: .top) {
                        statusBar
                    }
                    .toolbar {
                        ToolbarItemGroup(placement: .bottomBar) {
                            Button("键盘") { showKeyboard = true }
                            Button("Ctrl+Alt+Del") { session.sendCtrlAltDel() }
                            Button("Ctrl+C") { KeyboardBridge.sendCombo([0x11, 0x43], session: session) }
                            Button("Ctrl+V") { KeyboardBridge.sendCombo([0x11, 0x56], session: session) }
                            Button("关键帧") { session.requestKeyFrame() }
                            Spacer()
                            Text("\(session.fps, specifier: "%.1f") fps")
                                .font(.caption.monospacedDigit())
                            Button("断开") { session.disconnect() }
                        }
                    }
                    .alert("发送文字到远端", isPresented: $showKeyboard) {
                        TextField("输入文字", text: $keyboardText)
                        Button("发送") {
                            let text = keyboardText
                            keyboardText = ""
                            DispatchQueue.global(qos: .userInitiated).async {
                                KeyboardBridge.sendText(text, session: session)
                            }
                        }
                        Button("取消", role: .cancel) { }
                    } message: {
                        Text("ASCII 字符逐键发送；中文等请用剪贴板同步（复制后自动推送到远端）")
                    }
            } else {
                connectForm
            }
        }
        .navigationTitle("RemoteDesk")
        .navigationBarTitleDisplayMode(.inline)
        .onReceive(session.$toastMessage) { msg in
            if let m = msg { toast = m }
        }
        .overlay(alignment: .bottom) {
            if !toast.isEmpty {
                Text(toast)
                    .font(.footnote)
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .padding(.bottom, 60)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { toast = "" }
                    }
            }
        }
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
