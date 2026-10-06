import Foundation
import CoreGraphics

enum CaptureQualityState: Equatable {
    case unknown, passed, failed
}

/// 三項同時量測；角度欄也包含置中，避免三項全綠卻仍需移動臉部。
struct CaptureQuality: Equatable {
    let lighting: CaptureQualityState
    let angle: CaptureQualityState
    let size: CaptureQualityState
    static let unknown = CaptureQuality(lighting: .unknown, angle: .unknown, size: .unknown)

    static func measure(_ faces: [FaceMeasurement], configuration: CaptureConfiguration) -> CaptureQuality {
        guard configuration.isValid, faces.count == 1 else { return .unknown }
        let face = faces[0]
        let box = face.bounds
        guard !box.isNull, !box.isEmpty,
              [box.minX, box.minY, box.maxX, box.maxY].allSatisfy({ $0.isFinite }),
              !box.intersection(CGRect(x: 0, y: 0, width: 1, height: 1)).isEmpty else { return .unknown }
        let complete = box.minX >= 0 && box.minY >= 0 && box.maxX <= 1 && box.maxY <= 1
        let lighting: CaptureQualityState = !face.brightness.isFinite ? .unknown :
            (configuration.minimumBrightness...configuration.maximumBrightness).contains(face.brightness) ? .passed : .failed
        let centered = abs(box.midX - 0.5) <= configuration.centerTolerance &&
            abs(box.midY - 0.52) <= configuration.centerTolerance
        let angles = [face.yaw, face.roll, face.pitch]
        let angle = complete && face.poseReliable && centered && angles.allSatisfy { value in
            guard let value else { return false }
            return value.isFinite && abs(value) <= configuration.maximumAngle
        }
        let size = complete && CapturePreviewGeometry.faceHeightRange(configuration: configuration).contains(box.height)
        return CaptureQuality(lighting: lighting,
                              angle: angle ? .passed : .failed,
                              size: size ? .passed : .failed)
    }
}
