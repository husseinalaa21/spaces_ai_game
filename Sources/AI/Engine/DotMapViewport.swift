import Foundation
import CoreGraphics

/// Camera coordinates are screen points, independent of the world's zoom level.
struct DotMapViewport {
    private(set) var offset: CGSize
    private(set) var scale: CGFloat
    let limits: ClosedRange<CGFloat>
    private var lastPan = CGSize.zero
    private var panSuppressed = false
    private var panActive = false
    private var rebasePan = false
    private var pinchStart: (scale: CGFloat, offset: CGSize, anchor: CGPoint)?

    init(offset: CGSize = .zero, scale: CGFloat, limits: ClosedRange<CGFloat>) {
        self.offset = offset
        self.scale = min(limits.upperBound, max(limits.lowerBound, scale))
        self.limits = limits
    }

    mutating func pan(to translation: CGSize) {
        panActive = true
        guard !panSuppressed else { return }
        if pinchStart != nil || rebasePan {
            lastPan = translation
            rebasePan = pinchStart != nil
            return
        }
        offset.width += translation.width - lastPan.width
        offset.height += translation.height - lastPan.height
        lastPan = translation
    }

    mutating func endPan() {
        lastPan = .zero
        panActive = false
        panSuppressed = false
        rebasePan = false
    }

    mutating func pinch(to magnification: CGFloat, anchor: CGPoint) {
        guard magnification.isFinite, magnification > 0 else { return }
        if pinchStart == nil {
            pinchStart = (scale, offset, anchor)
            // Rebase the remaining finger before resuming its cumulative drag.
            rebasePan = panActive
        }
        guard let start = pinchStart else { return }
        scale = min(limits.upperBound, max(limits.lowerBound, start.scale * magnification))
        let ratio = scale / start.scale
        offset = CGSize(width: start.anchor.x + (start.offset.width - start.anchor.x) * ratio,
                        height: start.anchor.y + (start.offset.height - start.anchor.y) * ratio)
    }

    mutating func endPinch() {
        if pinchStart != nil { rebasePan = panActive }
        pinchStart = nil
    }

    mutating func suspendPan() {
        endPinch()
        panSuppressed = true
    }

    mutating func cancelGestures() {
        endPan()
        endPinch()
    }

    mutating func zoom(to target: CGFloat) {
        guard target.isFinite else { return }
        let next = min(limits.upperBound, max(limits.lowerBound, target))
        let ratio = next / scale
        offset = CGSize(width: offset.width * ratio, height: offset.height * ratio)
        scale = next
        cancelGestures()
    }

    mutating func reset(offset: CGSize = .zero, scale: CGFloat) {
        self.offset = offset
        self.scale = min(limits.upperBound, max(limits.lowerBound, scale))
        cancelGestures()
    }

    /// Coarsen the world grid at distant zooms while keeping its origin and motion aligned.
    var gridSpacing: CGFloat {
        var spacing = 44 * scale
        while spacing < 18 { spacing *= 2 }
        return spacing
    }
}
