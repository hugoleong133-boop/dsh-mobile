import Foundation
import VideoToolbox
import CoreMedia

/// H.264 Annex B 解码器（VideoToolbox 硬解）。
/// 输入：Annex B access unit（起始码分隔，可能含 SPS/PPS/IDR）
/// 输出：CMSampleBuffer（可直接喂 AVSampleBufferDisplayLayer 渲染）
///
/// 使用 iOS 15+ 的 outputHandler 变体：
///   VTDecompressionSessionCreate(outputCallback: nil)
///   VTDecompressionSessionDecodeFrame(... frameRefcon: outputHandler:)
/// 不再需要 VTDecompressionOutputCallbackRecord 老式回调。
final class H264Decoder {

    private var session: VTDecompressionSession?
    private var formatDesc: CMVideoFormatDescription?
    private var sps: [UInt8] = []
    private var pps: [UInt8] = []
    private var frameIndex: Int64 = 0

    init?(width: Int, height: Int) {
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey as String: max(width, 1),
            kCVPixelBufferHeightKey as String: max(height, 1),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var s: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: nil,
            formatDescription: nil,
            decoderSpecification: [
                kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder as String: true
            ] as CFDictionary,
            imageBufferAttributes: attrs as CFDictionary,
            outputCallback: nil,
            decompressionSessionOut: &s)
        guard status == noErr, let session = s else { return nil }
        self.session = session
    }

    deinit {
        if let s = session { VTDecompressionSessionInvalidate(s) }
    }

    /// 喂一个 Annex B access unit，返回可渲染的 CMSampleBuffer（或 nil）。
    func decode(_ annexB: [UInt8]) -> CMSampleBuffer? {
        guard let session = session else { return nil }

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

        guard let fd = formatDesc else { return nil }

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

        // 4. 解码（outputHandler 变体，返回解码后的 image buffer）
        var output: CMSampleBuffer?
        let status = VTDecompressionSessionDecodeFrame(
            session, sampleBuffer: sb,
            flags: [._EnableTemporalProcessing],
            frameRefcon: nil) { status, _, imageBuffer, _, _ in
            guard status == noErr, let pb = imageBuffer else { return }
            var fmt: CMVideoFormatDescription?
            CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pb, formatDescriptionOut: &fmt)
            if let f = fmt {
                var out: CMSampleBuffer?
                CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pb,
                                                         formatDescription: f,
                                                         sampleTiming: &timing, sampleBufferOut: &out)
                output = out
            }
        }
        _ = status
        return output
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
