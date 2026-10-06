import Foundation

/// 倒數只累積可拍攝的時間；短暫失效時暫停，避免一幀波動就重來。
struct CaptureCountdown {
    private var startedAt: TimeInterval?
    private var pausedAt: TimeInterval?
    var isPaused: Bool { pausedAt != nil }

    mutating func start(at timestamp: TimeInterval) {
        startedAt = timestamp
        pausedAt = nil
    }

    mutating func setPaused(_ paused: Bool, at timestamp: TimeInterval) {
        guard let startedAt else { return }
        if paused {
            if pausedAt == nil { pausedAt = timestamp }
        } else if let pausedAt {
            self.startedAt = startedAt + timestamp - pausedAt
            self.pausedAt = nil
        }
    }

    func remaining(at timestamp: TimeInterval, duration: TimeInterval) -> TimeInterval? {
        guard let startedAt, pausedAt == nil else { return nil }
        return duration - (timestamp - startedAt)
    }

    mutating func reset() {
        startedAt = nil
        pausedAt = nil
    }
}
