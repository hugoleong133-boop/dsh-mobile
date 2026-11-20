import SwiftUI
import AVFoundation

/// 远程画面渲染 + 触摸手势映射。
/// 渲染走 AVSampleBufferDisplayLayer（VideoToolbox 解码后直接 enqueue，零拷贝到 GPU）。
struct RemoteView: UIViewRepresentable {

    let session: Session

    func makeUIView(context: Context) -> RemoteUIView {
        let view = RemoteUIView(session: session)
        return view
    }

    func updateUIView(_ uiView: RemoteUIView, context: Context) {
        uiView.updateLayerFrame()
    }
}

final class RemoteUIView: UIView {

    private let session: Session
    private var lastDragTranslation: CGSize = .zero
    private var longPressRecognizer: UILongPressGestureRecognizer?
    private var tapRecognizer: UITapGestureRecognizer?
    private var panRecognizer: UIPanGestureRecognizer?
    private var pinchRecognizer: UIPinchGestureRecognizer?

    init(session: Session) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = .black
        layer.addSublayer(session.displayLayer)

        setupGestures()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateLayerFrame()
    }

    func updateLayerFrame() {
        session.displayLayer.frame = bounds
    }

    // MARK: - 手势

    private func setupGestures() {
        isMultipleTouchEnabled = true

        // 单指拖动 = 鼠标移动
        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = self
        addGestureRecognizer(pan)
        panRecognizer = pan

        // 单指点击 = 左键
        let tap = UITapGestureRecognizer(target: self, action: #selector(onTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.delegate = self
        addGestureRecognizer(tap)
        tapRecognizer = tap

        // 长按 = 右键
        let long = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        long.minimumPressDuration = 0.5
        addGestureRecognizer(long)
        longPressRecognizer = long

        // 双指拖动 = 滚动
        let twoPan = UIPanGestureRecognizer(target: self, action: #selector(onTwoFingerPan(_:)))
        twoPan.minimumNumberOfTouches = 2
        twoPan.maximumNumberOfTouches = 2
        twoPan.delegate = self
        addGestureRecognizer(twoPan)
    }

    private func normalized(_ point: CGPoint) -> (CGFloat, CGFloat) {
        guard bounds.width > 0, bounds.height > 0 else { return (0, 0) }
        return (point.x / bounds.width, point.y / bounds.height)
    }

    @objc private func onPan(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        let (x, y) = normalized(p)
        session.sendMouseMove(xNorm: x, yNorm: y)
    }

    @objc private func onTap(_ g: UITapGestureRecognizer) {
        let p = g.location(in: self)
        let (x, y) = normalized(p)
        // 按下 + 抬起
        session.sendMouseButton(buttons: 1, xNorm: x, yNorm: y)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.session.sendMouseButton(buttons: 0, xNorm: x, yNorm: y)
        }
    }

    @objc private func onLongPress(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        let p = g.location(in: self)
        let (x, y) = normalized(p)
        session.sendMouseButton(buttons: 2, xNorm: x, yNorm: y)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.session.sendMouseButton(buttons: 0, xNorm: x, yNorm: y)
        }
    }

    @objc private func onTwoFingerPan(_ g: UIPanGestureRecognizer) {
        let t = g.translation(in: self)
        let dy = t.y - lastDragTranslation.y
        lastDragTranslation = t
        if g.state == .began { lastDragTranslation = .zero; return }
        // 向上拖 = 滚轮向上（正值）
        let lines = Int32(-dy / 3.0)
        if lines != 0 { session.sendScroll(delta: lines * 40) }
    }
}

extension RemoteUIView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
