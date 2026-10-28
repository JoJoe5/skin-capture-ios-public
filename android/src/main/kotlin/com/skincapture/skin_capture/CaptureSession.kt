package com.skincapture.skin_capture

import java.lang.ref.WeakReference
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

internal data class CapturePhoto(val bytes: ByteArray, val width: Int, val height: Int, val capturedAt: Long) {
    fun toMap(): Map<String, Any> = mapOf(
        "jpegBytes" to bytes, "width" to width, "height" to height,
        "mimeType" to "image/jpeg", "capturedAtMilliseconds" to capturedAt,
    )
}

internal data class CaptureOutcome(val photo: CapturePhoto? = null, val code: String? = null, val message: String? = null)
internal class CaptureSession(val configuration: CaptureConfiguration) {
    var activity: WeakReference<SkinCaptureActivity>? = null
    var outcome: CaptureOutcome? = null
}

// 照片只存於目前程序的記憶體，不經 Intent 傳送，避免大型 JPEG 超過 Binder 上限。
internal object CaptureSessions {
    private val sessions = ConcurrentHashMap<String, CaptureSession>()
    fun create(config: CaptureConfiguration): String = UUID.randomUUID().toString().also {
        sessions[it] = CaptureSession(config)
    }
    fun get(id: String?): CaptureSession? = id?.let { sessions[it] }
    fun remove(id: String?): CaptureSession? = id?.let { sessions.remove(it) }
}
