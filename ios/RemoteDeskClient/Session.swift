import Foundation
import Network
import AVFoundation
import CoreMedia
import UIKit
import Combine

/// iOS 主控端会话：握手 → UDP 收视频 → 解码 → 渲染；触摸/键盘 → UDP 输入。
final class Session: ObservableObject {

    @Published var connected = false
    @Published var statusText = "未连接"
    @Published var fps: Double = 0
    @Published var toastMessage: String? = nil

    let displayLayer = AVSampleBufferDisplayLayer()
    let touchRelay = TouchRelay()

    private var udp: NWConnection?
    private var decoder: H264Decoder?
    private let queue = DispatchQueue(label: "rd.client", qos: .userInteractive)

    // 帧重组
    private var currentFrameId: UInt32 = 0
    private var frameParts: [Int: [UInt8]] = [:]
    private var frameCount: UInt16 = 0
    private var frameKeyFrame = false
    private var frameChunkSize: Int = 0
    private var frameReceivedBytes = 0

    private var statsTimer: Timer?

    private var remote: Protocol.Handshake?

    // MARK: - 连接

    func connect(host: String, port: UInt16, password: String,
                 onError: @escaping (String) -> Void) {
        let conn = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        conn.start(queue: queue)

        let req = Protocol.writeHandshakeRequest(password: password)
        conn.send(content: Data(req), completion: .contentProcessed { [weak self] _ in
            self?.receiveHandshake(conn, onError: onError)
        })
    }

    private func receiveHandshake(_ conn: NWConnection, onError: @escaping (String) -> Void) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, err in
            guard let self = self else { return }
            guard let data = data, let hs = Protocol.readHandshakeReply([UInt8](data)) else {
                onError("握手失败：密码错误或对端未启动")
                return
            }
            self.remote = hs
            self.startUdp(host: conn.endpoint, hs: hs)
            conn.cancel()

            DispatchQueue.main.async {
                self.connected = true
                self.statusText = "已连接 \(hs.machineName)  \(hs.screenWidth)x\(hs.screenHeight)"
            }
        }
    }

    private func startUdp(host: NWEndpoint, hs: Protocol.Handshake) {
        guard case let .hostPort(hostName, _) = host else { return }
        let udp = NWConnection(host: hostName, port: NWEndpoint.Port(rawValue: UInt16(hs.udpPort))!, using: .udp)
        udp.start(queue: queue)
        self.udp = udp

        let screenW = hs.screenWidth
        let screenH = hs.screenHeight
        decoder = H264Decoder(width: screenW, height: screenH)

        receiveUdp()
        startStats()
    }

    private func receiveUdp() {
        udp?.receive(minimumIncompleteLength: 1, maximumLength: 65535) { [weak self] data, _, _, err in
            guard let self = self else { return }
            if let data = data {
                self.onPacket([UInt8](data))
            }
            if err == nil { self.receiveUdp() }
        }
    }

    private var lastFpsCalc = Date().timeIntervalSince1970
    private var framesInWindow = 0

    private func onPacket(_ buf: [UInt8]) {
        // 剪贴板（16 字节头 + UTF-8 文本，Host 端可能分片）
        if buf.count >= 16, Protocol.getUInt32(buf, 0) == Protocol.clipboardMagic, buf[5] == 5 {
            let source = buf[6]
            if source == 2 {
                // Host → iOS
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
            // 新帧开始
            frameParts.removeAll()
            currentFrameId = hdr.frameId
            frameCount = hdr.count
            frameKeyFrame = hdr.keyFrame
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

    /// 是否启用剪贴板同步。
    public var ClipboardSync = true

    /// 检测本机剪贴板变化并推给 Host。由统计定时器每秒调用。
    public func pollClipboard() {
        guard ClipboardSync, connected, udp != nil else { return }
        let text = UIPasteboard.general.string ?? ""
        guard !text.isEmpty, text != lastClipboard else { return }
        lastClipboard = text
        if text == clipboardEcho { clipboardEcho = nil; return }

        let bytes = Array(text.utf8)
        guard bytes.count <= ClipboardPacket.maxTextBytes else { return }
        clipboardSeq &+= 1

        // 按 MTU 分片（与 Windows 端 ClipboardPacket.CreateDatagrams 对齐）
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

    public var ClipboardSent: Int = 0
    public var ClipboardReceived: Int = 0

    private func putClipboardHeader(_ b: inout [UInt8], seq: UInt32, total: Int) {
        // magic RDCB LE: 52 44 43 42
        b[0] = 0x52; b[1] = 0x44; b[2] = 0x43; b[3] = 0x42
        b[4] = 1                      // version
        b[5] = 5                      // Clipboard
        b[6] = 1                      // source = client
        b[7] = 1                      // UTF-8
        Protocol.putUInt32(seq, &b, 8)
        Protocol.putInt32(Int32(total), &b, 12)
    }

    /// 把远端剪贴板写到本机 UIPasteboard。
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
        udp?.send(content: Data(bytes), completion: .contentProcessed { _ in })
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

            // 顺带检查本机剪贴板，有变化就推给 Host
            self.pollClipboard()
        }
    }

    func disconnect() {
        send(Protocol.control(.bye))
        udp?.cancel()
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
    /// 当前按下的鼠标键位（bit0 左、bit1 右、bit2 中）。
    var buttons: UInt8 = 0

    /// 单指点击 = 左键。
    var onTap: ((CGFloat, CGFloat) -> Void)?
    /// 双指拖 = 滚动。
    var onScroll: ((Int32) -> Void)?
    /// 长按 = 右键。
    var onLongPress: ((CGFloat, CGFloat) -> Void)?
    /// 移动。
    var onMove: ((CGFloat, CGFloat) -> Void)?
}
