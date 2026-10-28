package com.skincapture.skin_capture

import kotlin.math.abs
import kotlin.math.max

// 分析統一使用正向、非鏡像影像，原點在左上；中心對應 iOS 左下座標的 0.52。
data class FaceBounds(val left: Double, val top: Double, val right: Double, val bottom: Double) {
    val width get() = right - left
    val height get() = bottom - top
    val centerX get() = (left + right) / 2
    val centerY get() = (top + bottom) / 2
    val valid get() = listOf(left, top, right, bottom).all { it.isFinite() } && width > 0 && height > 0
    val complete get() = valid && left >= 0 && top >= 0 && right <= 1 && bottom <= 1
    val intersects get() = valid && right > 0 && bottom > 0 && left < 1 && top < 1
}

data class FaceMeasurement(
    val bounds: FaceBounds, val yaw: Double, val pitch: Double, val roll: Double,
    val brightness: Double, val poseReliable: Boolean = true,
)

enum class QualityState { UNKNOWN, PASSED, FAILED }
data class CaptureQuality(
    val lighting: QualityState = QualityState.UNKNOWN,
    val angle: QualityState = QualityState.UNKNOWN,
    val size: QualityState = QualityState.UNKNOWN,
) {
    companion object {
        fun measure(faces: List<FaceMeasurement>, config: CaptureConfiguration): CaptureQuality {
            if (!config.isValid || faces.size != 1 || !faces[0].bounds.intersects) return CaptureQuality()
            val face = faces[0]
            fun status(value: Boolean) = if (value) QualityState.PASSED else QualityState.FAILED
            return CaptureQuality(
                if (!face.brightness.isFinite()) QualityState.UNKNOWN else
                    status(face.brightness in config.minimumBrightness..config.maximumBrightness),
                status(face.bounds.complete && face.poseReliable && centered(face.bounds, config) &&
                    config.acceptsPose(face.yaw, face.pitch, face.roll)),
                status(face.bounds.complete && face.bounds.height in
                    config.minimumFaceHeight * GUIDE_HEIGHT..config.maximumFaceHeight * GUIDE_HEIGHT),
            )
        }
    }
}

const val GUIDE_HEIGHT = 0.75
private fun centered(box: FaceBounds, config: CaptureConfiguration) =
    abs(box.centerX - 0.5) <= config.centerTolerance && abs(box.centerY - 0.48) <= config.centerTolerance

enum class Guidance(val key: String, val message: String) {
    NO_FACE("noFace", "請將臉部放入框內"),
    MULTIPLE_FACES("multipleFaces", "畫面中請只保留一張臉"),
    MOVE_CLOSER("moveCloser", "距離太遠\n請靠近一點"),
    MOVE_AWAY("moveAway", "距離太近\n請遠離一點"),
    CENTER_FACE("centerFace", "請將臉部移到畫面中央"),
    FACE_FORWARD("faceForward", "請調整轉頭角度，保持頭部端正"),
    MORE_LIGHT("moreLight", "光線不足\n請移到明亮且均勻的光源前"),
    LESS_LIGHT("lessLight", "光線太強\n請避開直射光"),
    HOLD_STILL("holdStill", "請保持不動"),
    READY("ready", "準備完成，可以拍照"),
}

data class GuidanceEvaluation(
    val guidance: Guidance, val progress: Double = 0.0, val canCapture: Boolean = false,
    val quality: CaptureQuality = CaptureQuality(), val blockingGuidance: Guidance? = null,
    val yawDegrees: Double? = null,
)

class GuidanceEvaluator(private val config: CaptureConfiguration) {
    private var stableSince: Double? = null
    private var previousTimestamp: Double? = null
    private var previousBounds: FaceBounds? = null
    private var invalidSince: Double? = null
    private var lastProgress = 0.0

    fun reset() {
        stableSince = null
        previousTimestamp = null
        previousBounds = null
        invalidSince = null
        lastProgress = 0.0
    }

    fun evaluate(faces: List<FaceMeasurement>, timestamp: Double): GuidanceEvaluation {
        val quality = if (timestamp.isFinite()) CaptureQuality.measure(faces, config) else CaptureQuality()
        val result = evaluateGuidance(faces, timestamp)
        val yaw = faces.singleOrNull()?.takeIf { quality != CaptureQuality() }?.yaw
            ?.takeIf { it.isFinite() }?.let { Math.toDegrees(it) }
        return result.copy(quality = quality, yawDegrees = yaw)
    }

    private fun evaluateGuidance(faces: List<FaceMeasurement>, timestamp: Double): GuidanceEvaluation {
        if (!config.isValid || !timestamp.isFinite()) return reject(Guidance.NO_FACE)
        previousTimestamp?.let { if (timestamp <= it || timestamp - it > 0.5) reset() }
        invalidSince?.let { if (timestamp - it >= 0.35) reset() }
        previousTimestamp = timestamp
        if (faces.size != 1) return reject(if (faces.isEmpty()) Guidance.NO_FACE else Guidance.MULTIPLE_FACES)
        val face = faces[0]
        val box = face.bounds
        if (!box.complete) return reject(Guidance.CENTER_FACE)
        if (!face.poseReliable || !listOf(face.yaw, face.pitch, face.roll).all { it.isFinite() }) {
            return reject(Guidance.FACE_FORWARD)
        }
        if (box.height < config.minimumFaceHeight * GUIDE_HEIGHT) return temporarilyReject(Guidance.MOVE_CLOSER, timestamp)
        if (box.height > config.maximumFaceHeight * GUIDE_HEIGHT) return temporarilyReject(Guidance.MOVE_AWAY, timestamp)
        if (!centered(box, config)) return temporarilyReject(Guidance.CENTER_FACE, timestamp)
        if (!config.acceptsPose(face.yaw, face.pitch, face.roll)) return temporarilyReject(Guidance.FACE_FORWARD, timestamp)
        if (!face.brightness.isFinite()) return reject(Guidance.MORE_LIGHT)
        if (face.brightness < config.minimumBrightness) return temporarilyReject(Guidance.MORE_LIGHT, timestamp)
        if (face.brightness > config.maximumBrightness) return temporarilyReject(Guidance.LESS_LIGHT, timestamp)
        previousBounds?.let {
            if (max(max(abs(box.centerX - it.centerX), abs(box.centerY - it.centerY)),
                    max(abs(box.width - it.width), abs(box.height - it.height))) > 0.05) {
                // 使用當下位置作為下一幀基準，避免移動後永遠無法重新穩定。
                previousBounds = box
                return temporarilyReject(Guidance.HOLD_STILL, timestamp)
            }
        }
        invalidSince?.let { paused -> stableSince = stableSince?.plus(timestamp - paused) }
        invalidSince = null
        previousBounds = box
        if (stableSince == null) stableSince = timestamp
        lastProgress = ((timestamp - stableSince!!) / config.stableDuration).coerceIn(0.0, 1.0)
        return GuidanceEvaluation(if (lastProgress >= 1) Guidance.READY else Guidance.HOLD_STILL,
            lastProgress, lastProgress >= 1)
    }

    private fun temporarilyReject(guidance: Guidance, timestamp: Double): GuidanceEvaluation {
        if (stableSince == null) return reject(guidance)
        if (invalidSince == null) invalidSince = timestamp
        if (timestamp - invalidSince!! >= 0.35) return reject(guidance)
        return GuidanceEvaluation(if (lastProgress >= 1) Guidance.READY else Guidance.HOLD_STILL,
            lastProgress, blockingGuidance = guidance)
    }

    private fun reject(guidance: Guidance): GuidanceEvaluation {
        reset()
        return GuidanceEvaluation(guidance)
    }
}

class CaptureCountdown {
    private var startedAt: Double? = null
    private var pausedAt: Double? = null
    fun start(timestamp: Double) { startedAt = timestamp; pausedAt = null }
    fun setPaused(paused: Boolean, timestamp: Double) {
        if (startedAt == null) return
        if (paused) {
            if (pausedAt == null) pausedAt = timestamp
        } else {
            pausedAt?.let { startedAt = startedAt!! + timestamp - it }
            pausedAt = null
        }
    }
    fun remaining(timestamp: Double, duration: Double): Double? =
        if (pausedAt != null) null else startedAt?.let { duration - (timestamp - it) }
    fun reset() { startedAt = null; pausedAt = null }
}
