import Foundation
import VideoToolbox
import CoreMedia

/// H.264 Annex B 解码器（VideoToolbox 硬解）。
/// 输入：Annex B access unit（起始码分隔，可能含 SPS/PPS/IDR）
/// 输出：CMSampleBuffer（可直接喂 AVSampleBufferDisplayLayer 渲染）
///
/// 用最保守的老式回调 API（所有 iOS/macOS SDK 版本都有）：
///   VTDecompressionSessionCreate(outputCallback:&cb)
///   VTDecompressionSessionDecodeFrame(... frameRefcon: infoFlagsOut:)
final class H264Decoder {

    private var session: VTDecompressionSession?
    private var formatDesc: CMVideoFormatDescription?
    private var sps: [UInt8] = []
    private var pps: [UInt8] = []
    private var frameIndex: Int64 = 0

    private let lock = NSLock()
    private var decodedImage: CVImageBuffer?
    private let width: Int
    private let height: Int

    init?(width: Int, height: Int) {
        self.width = max(width, 1)
        self.height = max(height, 1)
        // session 延迟到拿到 SPS/PPS 建立 formatDesc 后再创建
    }

    deinit {
        if let s = session { VTDecompressionSessionInvalidate(s) }
    }

    /// 有 formatDesc 后创建解码会话（formatDescription 参数非可选，必须等 SPS/PPS）。
    private func ensureSession() {
        guard session == nil, let fd = formatDesc else { return }

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]

        // 老式输出回调：解码器把 image buffer 经 refCon 存回 self
        var cb = VTDecompressionOutputCallbackRecord()
        cb.decompressionOutputCallback = {
            (refCon: UnsafeMutableRawPointer?, _: UnsafeMutableRawPointer?,
             status: OSStatus, _: VTDecodeInfoFlags,
             imageBuffer: CVImageBuffer?, _: CMTime, _: CMTime) in
            guard status == noErr, let imageBuffer = imageBuffer,
                  let refCon = refCon else { return }
            let decoder = Unmanaged<H264Decoder>.fromOpaque(refCon).takeUnretainedValue()
            decoder.lock.lock()
            decoder.decodedImage = imageBuffer
            decoder.lock.unlock()
        }
        cb.decompressionOutputRefCon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())

        var s: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: fd,
            decoderSpecification: nil,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: &cb,
            decompressionSessionOut: &s)
        guard status == noErr, let session = s else { return }
        self.session = session
    }

    /// 喂一个 Annex B access unit，返回可渲染的 CMSampleBuffer（或 nil）。
    func decode(_ annexB: [UInt8]) -> CMSampleBuffer? {
        // 1. 拆 NAL
        var nals: [[UInt8]] = []
        var i = 0
        let n = annexB.count
        while i + 3 < n {
            if annexB[i] == 0 && annexB[i + 1] == 0 && annexB[i + 2] == 1 {
                let start = i + 3
                var end = start
                while end + 3 < n {
                    if annexB[end] == 0 && annexB[end + 1] == 0 && annexB[end + 2] == 1 { break }
                    end += 1
                }
                let nal = Array(annexB[start..<end])
                if !nal.isEmpty { nals.append(nal) }
                i = end
            } else if annexB[i] == 0 && annexB[i + 1] == 0 && annexB[i + 2] == 0 && annexB[i + 3] == 1 {
                let start = i + 4
                var end = start
                while end + 3 < n {
                    if (annexB[end] == 0 && annexB[end + 1] == 0 && annexB[end + 2] == 1) ||
                       (annexB[end] == 0 && annexB[end + 1] == 0 && annexB[end + 2] == 0 && annexB[end + 3] == 1) { break }
                    end += 1
                }
                nals.append(Array(annexB[start..<end]))
                i = end
            } else { i += 1 }
        }

        // 2. 提取 SPS/PPS 并建立 format description
        var newSps: [UInt8]? = nil
        var newPps: [UInt8]? = nil
        for nal in nals {
            let type = nal.first.map { $0 & 0x1F } ?? 0
            if type == 7 { newSps = nal }
            if type == 8 { newPps = nal }
        }
        if let s = newSps, let p = newPps, s != sps || p != pps {
            sps = s; pps = p
            rebuildFormatDescription()
        }

        ensureSession()
        guard let fd = formatDesc, let session = session else { return nil }

        // 3. Annex B → 4 字节长度前缀（VT 需要 avcC 格式）
        var avcc = [UInt8]()
        for nal in nals {
            var len = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &len) { avcc.append(contentsOf: $0) }
            avcc.append(contentsOf: nal)
        }

        var block: CMBlockBuffer?
        avcc.withUnsafeBytes { raw in
            CMBlockBufferCreateWithMemoryBlock(
                allocator: nil, memoryBlock: nil, blockLength: avcc.count,
                blockAllocator: nil, customBlockSource: nil, offsetToData: 0,
                dataLength: avcc.count, flags: 0, blockBufferOut: &block)
            if let bb = block {
                CMBlockBufferReplaceDataBytes(with: raw.baseAddress!, blockBuffer: bb,
                                              offsetIntoDestination: 0, dataLength: avcc.count)
            }
        }
        guard let bb = block else { return nil }

        let pts = CMTime(value: frameIndex, timescale: 60)
        frameIndex += 1
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60),
                                        presentationTimeStamp: pts,
                                        decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        CMSampleBufferCreateReady(allocator: nil, dataBuffer: bb, formatDescription: fd,
                                  sampleCount: 1, sampleTimingEntryCount: 1,
                                  sampleTimingArray: &timing, sampleSizeEntryCount: 0,
                                  sampleSizeArray: nil, sampleBufferOut: &sample)
        guard let sb = sample else { return nil }

        // 4. 老式解码：结果经 outputCallback 存到 decodedImage
        lock.lock()
        decodedImage = nil
        lock.unlock()

        var flagsOut = VTDecodeInfoFlags()
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sb,
                                          flags: [._EnableTemporalProcessing],
                                          frameRefcon: nil,
                                          infoFlagsOut: &flagsOut)

        lock.lock()
        let image = decodedImage
        decodedImage = nil
        lock.unlock()

        guard let pb = image else { return nil }

        var fmt: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
        guard let f = fmt else { return nil }

        var out: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb,
                                                 formatDescription: f,
                                                 sampleTiming: &timing, sampleBufferOut: &out)
        return out
    }

    private func rebuildFormatDescription() {
        formatDesc = nil
        guard !sps.isEmpty, !pps.isEmpty else { return }

        let spsLen = sps.count, ppsLen = pps.count

        sps.withUnsafeBufferPointer { spsPtr in
            pps.withUnsafeBufferPointer { ppsPtr in
                guard let sp = spsPtr.baseAddress, let pp = ppsPtr.baseAddress else { return }
                var paramPointers = [UnsafePointer<UInt8>(sp), UnsafePointer<UInt8>(pp)]
                var paramSizes = [spsLen, ppsLen]
                CMVideoFormatDescriptionCreateFromH264ParameterSets(
                    allocator: nil, parameterSetCount: 2,
                    parameterSetPointers: &paramPointers,
                    parameterSetSizes: &paramSizes,
                    nalUnitHeaderLength: 4, formatDescriptionOut: &formatDesc)
            }
        }
    }
}
