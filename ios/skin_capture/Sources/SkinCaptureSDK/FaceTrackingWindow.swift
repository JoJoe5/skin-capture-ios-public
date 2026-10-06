import Foundation

/// 追蹤只能短暫補上當下的區域量測，不能無限沿用舊的人臉位置。
struct FaceTrackingWindow {
    private var confirmedAt: TimeInterval?
    private var previousFrameAt: TimeInterval?

    mutating func confirm(at timestamp: TimeInterval) {
        confirmedAt = timestamp
        previousFrameAt = timestamp
    }

    mutating func reset() {
        confirmedAt = nil
        previousFrameAt = nil
    }

    mutating func allowTracking(at timestamp: TimeInterval) -> Bool {
        guard let confirmedAt, let previousFrameAt, timestamp.isFinite,
              timestamp > previousFrameAt, timestamp - previousFrameAt <= 0.5,
              timestamp - confirmedAt <= 2 else {
            reset()
            return false
        }
        self.previousFrameAt = timestamp
        return true
    }
}
