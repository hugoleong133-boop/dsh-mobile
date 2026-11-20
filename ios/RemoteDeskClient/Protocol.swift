import Foundation

/// RemoteDesk 协议编解码（iOS 客户端侧）。
/// 与 macOS 被控端 / Windows 端逐字节一致，规范见 docs/protocol-spec.md。
enum Protocol {

    static func putUInt32(_ v: UInt32, _ buf: inout [UInt8], _ off: Int) {
        buf[off] = UInt8(v & 0xFF); buf[off + 1] = UInt8((v >> 8) & 0xFF)
        buf[off + 2] = UInt8((v >> 16) & 0xFF); buf[off + 3] = UInt8((v >> 24) & 0xFF)
    }

    static func putUInt16(_ v: UInt16, _ buf: inout [UInt8], _ off: Int) {
        buf[off] = UInt8(v & 0xFF); buf[off + 1] = UInt8((v >> 8) & 0xFF)
    }

    static func putInt32(_ v: Int32, _ buf: inout [UInt8], _ off: Int) {
        putUInt32(UInt32(bitPattern: v), &buf, off)
    }

    static func getUInt32(_ buf: [UInt8], _ off: Int) -> UInt32 {
        UInt32(buf[off]) | (UInt32(buf[off + 1]) << 8) |
        (UInt32(buf[off + 2]) << 16) | (UInt32(buf[off + 3]) << 24)
    }

    static func getUInt16(_ buf: [UInt8], _ off: Int) -> UInt16 {
        UInt16(buf[off]) | (UInt16(buf[off + 1]) << 8)
    }

    static func getInt64(_ buf: [UInt8], _ off: Int) -> Int64 {
        var u: UInt64 = 0
        for i in 0..<8 { u |= UInt64(buf[off + i]) << (8 * i) }
        return Int64(bitPattern: u)
    }

    static func writeRdsString(_ s: String, _ buf: inout [UInt8], _ off: inout Int) {
        let bytes = Array(s.utf8)
        buf[off] = UInt8(bytes.count); off += 1
        bytes.withUnsafeBytes { raw in buf.replaceSubrange(off..<(off + bytes.count), with: raw) }
        off += bytes.count
    }

    static func writeHandshakeRequest(password: String) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: 512)
        var off = 0
        buf[off] = UInt8(ascii: "R"); buf[off + 1] = UInt8(ascii: "D")
        buf[off + 2] = UInt8(ascii: "H"); buf[off + 3] = UInt8(ascii: "S")
        off += 4
        putInt32(2, &buf, off); off += 4
        writeRdsString("ios-client", &buf, &off)
        writeRdsString(password, &buf, &off)
        putInt32(0, &buf, off); off += 4     // udpPort（回复里才填）
        putInt32(0, &buf, off); off += 4
        putInt32(0, &buf, off); off += 4
        writeRdsString("", &buf, &off)
        writeRdsString("", &buf, &off)
        writeRdsString("", &buf, &off)
        putInt32(0, &buf, off); off += 4
        return Array(buf[0..<off])
    }

    static func readRdsString(_ buf: [UInt8], _ off: inout Int) -> String? {
        guard off < buf.count else { return nil }
        let len = Int(buf[off]); off += 1
        guard off + len <= buf.count else { return nil }
        let s = String(bytes: buf[off..<(off + len)], encoding: .utf8)
        off += len
        return s
    }

    struct Handshake {
        var udpPort: Int = 0
        var screenWidth: Int = 0
        var screenHeight: Int = 0
        var machineName: String = ""
        var videoCodec: String = "h264"
        var captureBackend: String = ""
        var filePort: Int = 0
    }

    static func readHandshakeReply(_ buf: [UInt8]) -> Handshake? {
        guard buf.count >= 4, buf[0] == UInt8(ascii: "R"), buf[1] == UInt8(ascii: "D"),
              buf[2] == UInt8(ascii: "H"), buf[3] == UInt8(ascii: "S") else { return nil }
        var off = 4
        _ = getUInt32(buf, off); off += 4
        _ = readRdsString(buf, &off)          // deviceId
        _ = readRdsString(buf, &off)          // password（空）
        let udp = Int(Int32(bitPattern: getUInt32(buf, off))); off += 4
        let w = Int(Int32(bitPattern: getUInt32(buf, off))); off += 4
        let h = Int(Int32(bitPattern: getUInt32(buf, off))); off += 4
        let name = readRdsString(buf, &off) ?? ""
        let codec = readRdsString(buf, &off) ?? "h264"
        let backend = readRdsString(buf, &off) ?? ""
        let file = Int(Int32(bitPattern: getUInt32(buf, off)))
        return Handshake(udpPort: udp, screenWidth: w, screenHeight: h,
                         machineName: name, videoCodec: codec,
                         captureBackend: backend, filePort: file)
    }

    // 输入事件（16 字节）
    static let inputMagic: UInt32 = 0x4B52_4E49

    enum InputKind: UInt8 { case mouseMove = 1, mouseButton = 2, mouseWheel = 3, keyDown = 4, keyUp = 5 }

    static func input(_ kind: InputKind, x: UInt16, y: UInt16, data: Int32, buttons: UInt8) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 16)
        putUInt32(inputMagic, &b, 0); b[4] = 1; b[5] = 3
        b[6] = kind.rawValue; b[7] = buttons
        putUInt16(x, &b, 8); putUInt16(y, &b, 10); putInt32(data, &b, 12)
        return b
    }

    // 控制包
    static let videoMagic: UInt32 = 0x4B52_5244

    enum ControlKind: UInt8 {
        case ack = 1, nack = 2, requestKeyFrame = 3, bitrateHint = 4,
             ping = 5, pong = 6, displayInfo = 7, bye = 8,
             switchDisplay = 9, displayList = 10
    }

    static func control(_ kind: ControlKind, frameId: UInt32 = 0, value: Int32 = 0) -> [UInt8] {
        var b = [UInt8](repeating: 0, count: 16)
        putUInt32(videoMagic, &b, 0); b[4] = 1; b[5] = 4
        b[6] = kind.rawValue; b[7] = 0
        putUInt32(frameId, &b, 8); putInt32(value, &b, 12)
        return b
    }

    static func parseControl(_ buf: [UInt8]) -> (ControlKind, UInt32, Int32)? {
        guard buf.count >= 16, getUInt32(buf, 0) == videoMagic, buf[5] == 4 else { return nil }
        return (ControlKind(rawValue: buf[6]) ?? .bye, getUInt32(buf, 8),
                Int32(bitPattern: getUInt32(buf, 12)))
    }

    // 视频分片头（28 字节）
    struct VideoHeader {
        let frameId: UInt32
        let index: UInt16
        let count: UInt16
        let chunkSize: UInt16
        let payloadLen: UInt16
        let codec: UInt8
        let keyFrame: Bool
    }

    static func parseVideoHeader(_ buf: [UInt8]) -> VideoHeader? {
        guard buf.count >= 28, getUInt32(buf, 0) == videoMagic, buf[5] == 2 else { return nil }
        let count = getUInt16(buf, 14)
        let index = getUInt16(buf, 12)
        guard count > 0, index < count else { return nil }
        return VideoHeader(frameId: getUInt32(buf, 8), index: index, count: count,
                           chunkSize: getUInt16(buf, 16), payloadLen: getUInt16(buf, 18),
                           codec: buf[7], keyFrame: (buf[6] & 0x01) != 0)
    }

    // 剪贴板（16 字节头）
    static let clipboardMagic: UInt32 = 0x4243_4452

    static func clipboardHeader(_ buf: [UInt8]) -> (source: UInt8, seq: UInt32, total: Int)? {
        guard buf.count >= 16, getUInt32(buf, 0) == clipboardMagic, buf[5] == 5 else { return nil }
        return (buf[6], getUInt32(buf, 8), Int(Int32(bitPattern: getUInt32(buf, 12))))
    }
}
