import Foundation
import Network
import AVFoundation
import CoreMedia
import UIKit
import Combine

/// iOS 主控端会话：握手 → UDP 收视频 → 解码 → 渲染；触摸/键盘 → UDP 输入。
///
/// UDP 数据面用 BSD socket（bind 随机端口 → 端口写进握手包 → Host 往回发视频）。
/// 之前用 NWConnection 时握手请求里 udpPort=0，Host 不知道往哪发视频，画面黑屏。
final class Session: ObservableObject {

    @Published var connected = false
    @Published var statusText = "未连接"
    @Published var fps: Double = 0
    @Published var toastMessage: String? = nil

    let displayLayer = AVSampleBufferDisplayLayer()
    let touchRelay = TouchRelay()

    private var decoder: H264Decoder?
    private let queue = DispatchQueue(label: "rd.client", qos: .userInteractive)

    // TCP 握手连接
    private var tcp: NWConnection?

    // UDP 数据面（BSD socket）
    private var udpFd: Int32 = -1
    private var udpListenPort: UInt16 = 0
    private var remoteAddr = sockaddr_in()
    private var udpThread: Thread?
    private var udpRunning = false

    // 帧重组
    private var currentFrameId: UInt32 = 0
    private var frameParts: [Int: [UInt8]] = [:]
    private var frameCount: UInt16 = 0
    private var frameChunkSize: Int = 0
    private var frameReceivedBytes = 0

    private var statsTimer: Timer?
    private var remote: Protocol.Handshake?

    // MARK: - 连接

    func connect(host: String, port: UInt16, password: String,
                 onError: @escaping (String) -> Void) {
        // 1. 先绑定 UDP socket，拿到本地端口写进握手包
        guard openUdpSocket() else {
            onError("无法创建 UDP socket")
            return
        }

        // 2. TCP 握手（带真实 udpPort）
        let conn = NWConnection(host: NWEndpoint.Host(host),
                                port: NWEndpoint.Port(rawValue: port)!,
                                using: .tcp)
        tcp = conn
        conn.start(queue: queue)

        let req = Protocol.writeHandshakeRequest(password: password, udpPort: Int(udpListenPort))
        conn.send(content: Data(req), completion: .contentProcessed { [weak self] _ in
            self?.receiveHandshake(conn, hostStr: host, onError: onError)
        })
    }

    /// 绑定 UDP socket 并返回分配的本地端口。
    private func openUdpSocket() -> Bool {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return false }

        // 避免 withUnsafePointer 嵌套推断问题：memcpy 组装 sockaddr
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = 0                          // 系统分配
        sin.sin_addr.s_addr = INADDR_ANY

        var sa = sockaddr()
        memcpy(&sa, &sin, MemoryLayout<sockaddr_in>.size)
        let len = socklen_t(MemoryLayout<sockaddr_in>.size)

        guard bind(fd, &sa, len) == 0 else { close(fd); return false }

        var name = sockaddr_in()
        var nameSa = sockaddr()
        var nameLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        guard getsockname(fd, &nameSa, &nameLen) == 0 else { close(fd); return false }
        memcpy(&name, &nameSa, min(Int(nameLen), MemoryLayout<sockaddr_in>.size))

        udpFd = fd
        udpListenPort = UInt16(bigEndian: name.sin_port)
        return udpListenPort > 0
    }

    private func receiveHandshake(_ conn: NWConnection, hostStr: String,
                                  onError: @escaping (String) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, err in
            guard let self = self else { return }
            guard let data = data, let hs = Protocol.readHandshakeReply([UInt8](data)) else {
                onError("握手失败：密码错误或对端未启动")
                return
            }
            self.remote = hs

            // 解析 Host 地址（供 UDP sendto 用）
            self.fillRemoteAddr(hostStr: hostStr, udpPort: hs.udpPort)

            // 启动 UDP 接收线程
            self.startUdpReceive()

            // 建解码器（尺寸来自握手）
            self.decoder = H264Decoder(width: hs.screenWidth, height: hs.screenHeight)

            conn.cancel()   // TCP 握手完成，关闭

            DispatchQueue.main.async {
                self.connected = true
                self.statusText = "已连接 \(hs.machineName)  \(hs.screenWidth)x\(hs.screenHeight)"
            }
        }
    }

    private func fillRemoteAddr(hostStr: String, udpPort: Int) {
        var sin = sockaddr_in()
        sin.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        sin.sin_family = sa_family_t(AF_INET)
        sin.sin_port = in_port_t(bigEndian: in_port_t(truncatingIfNeeded: udpPort))

        var ok = false
        hostStr.withCString { cstr in
            ok = inet_pton(AF_INET, cstr, &sin.sin_addr) == 1
        }
        if !ok {
            var hints = addrinfo()
            hints.ai_family = AF_INET
            hints.ai_socktype = SOCK_DGRAM
            var result: UnsafeMutablePointer<addrinfo>?
            if getaddrinfo(hostStr, nil, &hints, &result) == 0, let first = result {
                var tmp = sockaddr_in()
                memcpy(&tmp, first.pointee.ai_addr, min(Int(first.pointee.ai_addrlen), MemoryLayout<sockaddr_in>.size))
                sin.sin_addr = tmp.sin_addr
                freeaddrinfo(result)
                ok = true
            }
        }
        var sa = sockaddr()
        memcpy(&sa, &sin, MemoryLayout<sockaddr_in>.size)
        remoteAddr = sa
    }

    // MARK: - UDP 接收线程

    private func startUdpReceive() {
        guard udpFd >= 0, !udpRunning else { return }
        udpRunning = true

        udpThread = Thread { [weak self] in
            guard let self = self else { return }
            let fd = self.udpFd
            var buf = [UInt8](repeating: 0, count: 65536)

            while self.udpRunning {
                var fromAddr = sockaddr()
                var fromLen = socklen_t(MemoryLayout<sockaddr>.size)
                let n = buf.withUnsafeMutableBytes { bufPtr in
                    recvfrom(fd, bufPtr.baseAddress, buf.count, 0, &fromAddr, &fromLen)
                }
                if n <= 0 {
                    if errno == EAGAIN || errno == EWOULDBLOCK { continue }
                    break
                }
                self.onPacket(Array(buf[0..<n]))
            }
        }
        udpThread?.name = "rd-udp-rx"
        udpThread?.start()
    }

    private var lastFpsCalc = Date().timeIntervalSince1970
    private var framesInWindow = 0

    private func onPacket(_ buf: [UInt8]) {
        // 剪贴板（16 字节头 + UTF-8 文本）
        if buf.count >= 16, Protocol.getUInt32(buf, 0) == Protocol.clipboardMagic, buf[5] == 5 {
            if buf[6] == 2 {
                if let text = clipAsm.push(buf) {
                    applyRemoteClipboard(text)
                }
            }
            return
        }

        if let (kind, frameId, value) = Protocol.parseControl(buf) {
            switch kind {
            case .ping:
                send(Protocol.control(.pong, frameId: frameId, value: value))
            default: break
            }
            return
        }

        guard let hdr = Protocol.parseVideoHeader(buf) else { return }
        let payload = Array(buf[28..<(28 + Int(hdr.payloadLen))])

        if hdr.frameId != currentFrameId {
            frameParts.removeAll()
            currentFrameId = hdr.frameId
            frameCount = hdr.count
            frameChunkSize = Int(hdr.chunkSize)
            frameReceivedBytes = 0
        }

        frameParts[Int(hdr.index)] = payload
        frameReceivedBytes += payload.count

        if frameParts.count >= Int(frameCount) {
            var au = [UInt8]()
            for i in 0..<Int(frameCount) {
                if let p = frameParts[i] { au += p }
            }
            frameParts.removeAll()

            if hdr.codec == 2, let sample = decoder?.decode(au) {
                DispatchQueue.main.async {
                    if self.displayLayer.status == .failed { self.displayLayer.flush() }
                    self.displayLayer.enqueue(sample)
                    self.framesInWindow += 1
                }
            }
        }
    }

    // MARK: - 剪贴板同步

    private let clipAsm = ClipboardAssembler()
    private var lastClipboard: String?
    private var clipboardEcho: String?
    private var clipboardSeq: UInt32 = 0

    public var ClipboardSync = true

    public var ClipboardSent: Int = 0
    public var ClipboardReceived: Int = 0

    /// 检测本机剪贴板变化并推给 Host。由统计定时器每秒调用。
    public func pollClipboard() {
        guard ClipboardSync, connected, udpFd >= 0 else { return }
        let text = UIPasteboard.general.string ?? ""
        guard !text.isEmpty, text != lastClipboard else { return }
        lastClipboard = text
        if text == clipboardEcho { clipboardEcho = nil; return }

        let bytes = Array(text.utf8)
        // 与 Windows 端 ClipboardPacket.MaxTextBytes 一致：64 KB 上限
        guard bytes.count <= 64 * 1024 else { return }
        clipboardSeq &+= 1

        let mtu = 1200, headerLen = 16
        let chunk = mtu - headerLen
        var off = 0
        while off < bytes.count || (off == 0 && bytes.isEmpty) {
            let len = min(chunk, bytes.count - off)
            var pkt = [UInt8](repeating: 0, count: headerLen + len)
            putClipboardHeader(&pkt, seq: clipboardSeq, total: bytes.count)
            if len > 0 {
                pkt.replaceSubrange(headerLen..<(headerLen + len), with: bytes[off..<(off + len)])
            }
            send(pkt)
            off += len
            if bytes.isEmpty { break }
        }
        ClipboardSent += 1
    }

    private func putClipboardHeader(_ b: inout [UInt8], seq: UInt32, total: Int) {
        b[0] = 0x52; b[1] = 0x44; b[2] = 0x43; b[3] = 0x42   // RDCB LE
        b[4] = 1; b[5] = 5; b[6] = 1; b[7] = 1
        Protocol.putUInt32(seq, &b, 8)
        Protocol.putInt32(Int32(total), &b, 12)
    }

    private func applyRemoteClipboard(_ text: String) {
        guard ClipboardSync, !text.isEmpty, text != lastClipboard else { return }
        lastClipboard = text
        clipboardEcho = text
        DispatchQueue.main.async {
            UIPasteboard.general.string = text
            self.ClipboardReceived += 1
            self.toastMessage = "已同步远端剪贴板：\(text.prefix(20))"
        }
    }

    // MARK: - 输入

    private func send(_ bytes: [UInt8]) {
        guard udpFd >= 0 else { return }
        var sa = sockaddr()
        memcpy(&sa, &remoteAddr, MemoryLayout<sockaddr_in>.size)
        bytes.withUnsafeBytes { raw in
            withUnsafePointer(to: &sa) { ptr in
                _ = sendto(udpFd, raw.baseAddress, bytes.count, 0, ptr,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
    }

    /// 触摸/键盘由 TouchRelay 回调到这里，统一发 UDP。
    func sendMouseMove(xNorm: CGFloat, yNorm: CGFloat) {
        let x = UInt16(max(0, min(1, xNorm)) * 65535)
        let y = UInt16(max(0, min(1, yNorm)) * 65535)
        send(Protocol.input(.mouseMove, x: x, y: y, data: 0, buttons: touchRelay.buttons))
    }

    func sendMouseButton(buttons: UInt8, xNorm: CGFloat, yNorm: CGFloat) {
        let x = UInt16(max(0, min(1, xNorm)) * 65535)
        let y = UInt16(max(0, min(1, yNorm)) * 65535)
        send(Protocol.input(.mouseButton, x: x, y: y, data: 0, buttons: buttons))
    }

    func sendScroll(delta: Int32) {
        send(Protocol.input(.mouseWheel, x: 0, y: 0, data: delta, buttons: 0))
    }

    func sendKey(vk: UInt16, down: Bool) {
        send(Protocol.input(down ? .keyDown : .keyUp, x: 0, y: 0, data: Int32(vk), buttons: 0))
    }

    func sendCtrlAltDel() {
        for vk in [UInt16(0x11), 0x12, 0x2E] { sendKey(vk: vk, down: true) }
        for vk in [UInt16(0x2E), 0x12, 0x11] { sendKey(vk: vk, down: false) }
    }

    func requestKeyFrame() {
        send(Protocol.control(.requestKeyFrame))
    }

    // MARK: - 统计

    private func startStats() {
        statsTimer?.invalidate()
        statsTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let now = Date().timeIntervalSince1970
            let dt = now - self.lastFpsCalc
            if dt > 0 {
                self.fps = Double(self.framesInWindow) / dt
            }
            self.framesInWindow = 0
            self.lastFpsCalc = now

            self.pollClipboard()
        }
    }

    func disconnect() {
        send(Protocol.control(.bye))
        udpRunning = false
        if udpFd >= 0 { close(udpFd); udpFd = -1 }
        statsTimer?.invalidate()
        decoder = nil
        DispatchQueue.main.async {
            self.connected = false
            self.statusText = "已断开"
        }
    }
}

/// 触摸 → 鼠标事件映射（iOS 手势语义）。
final class TouchRelay {
    var buttons: UInt8 = 0
    var onTap: ((CGFloat, CGFloat) -> Void)?
    var onScroll: ((Int32) -> Void)?
    var onLongPress: ((CGFloat, CGFloat) -> Void)?
    var onMove: ((CGFloat, CGFloat) -> Void)?
}
