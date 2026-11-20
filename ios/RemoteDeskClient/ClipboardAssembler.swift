import Foundation

/// 剪贴板分片重组器（与 Windows 端 ClipboardAssembler 对齐）。
/// 按 seq 收集分片，收齐 totalLen 字节时返回完整文本；新 seq 到达时丢弃旧片段。
final class ClipboardAssembler {

    private var seq: UInt32 = UInt32.max
    private var totalLen = 0
    private var buffer = [UInt8]()

    public func reset() {
        seq = UInt32.max
        totalLen = 0
        buffer.removeAll(keepingCapacity: true)
    }

    /// 推入一个分片 datagram。返回完整文本（收齐时）或 nil。
    public func push(_ datagram: [UInt8]) -> String? {
        guard datagram.count >= 16 else { return nil }
        let s = Protocol.getUInt32(datagram, 8)
        let total = Int(Int32(bitPattern: Protocol.getUInt32(datagram, 12)))
        guard total >= 0, total <= 64 * 1024 else { return nil }

        if s != seq {
            seq = s
            totalLen = total
            buffer.removeAll(keepingCapacity: true)
        }

        let payload = Array(datagram[16...])
        if payload.isEmpty {
            return total == 0 ? "" : nil
        }
        buffer.append(contentsOf: payload)

        if buffer.count >= totalLen {
            let text = String(bytes: buffer.prefix(totalLen), encoding: .utf8) ?? ""
            reset()
            return text
        }
        return nil
    }
}
