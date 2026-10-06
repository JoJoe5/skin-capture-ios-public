#if canImport(UIKit)
import CoreVideo
import Vision

/// 分析佇列專用；只追蹤剛辨識到的單張臉，不提供姿態或快門資格。
final class FaceRegionTracker {
    private var sequence = VNSequenceRequestHandler()
    private var request: VNTrackObjectRequest?
    private var window = FaceTrackingWindow()

    func reset() {
        request = nil
        sequence = VNSequenceRequestHandler()
        window.reset()
    }

    func confirm(_ face: VNFaceObservation, at timestamp: TimeInterval) {
        reset()
        request = VNTrackObjectRequest(detectedObjectObservation: face)
        request?.trackingLevel = .accurate
        window.confirm(at: timestamp)
    }

    func track(in buffer: CVPixelBuffer, at timestamp: TimeInterval) -> CGRect? {
        guard let request, window.allowTracking(at: timestamp) else { reset(); return nil }
        do {
            try sequence.perform([request], on: buffer, orientation: .up)
            guard let observation = request.results?.first as? VNDetectedObjectObservation, observation.confidence >= 0.5 else {
                reset()
                return nil
            }
            let box = observation.boundingBox
            guard !box.isNull, !box.isEmpty,
                  [box.minX, box.minY, box.maxX, box.maxY].allSatisfy({ $0.isFinite }),
                  box.minX >= 0, box.minY >= 0, box.maxX <= 1, box.maxY <= 1 else {
                reset()
                return nil
            }
            request.inputObservation = observation
            return box
        } catch {
            // 追蹤失敗回到待辨識，仍可在下一幀重新偵測，不把它當作相機故障。
            reset()
            return nil
        }
    }
}
#endif
