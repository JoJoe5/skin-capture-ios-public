package com.skincapture.skin_capture

import android.graphics.Bitmap
import android.graphics.Matrix
import androidx.camera.core.ImageProxy
import java.io.ByteArrayOutputStream
import kotlin.math.roundToInt

internal object PhotoProcessor {
    fun process(image: ImageProxy, config: CaptureConfiguration, capturedAt: Long): CapturePhoto {
        val raw = image.toBitmap()
        try {
            return process(raw, image.imageInfo.rotationDegrees, config, capturedAt)
        } finally { raw.recycle() }
    }

    // CameraX 回傳未鏡像的完整影像；旋轉烘焙到像素，重新編碼去除原始中繼資料。
    fun process(raw: Bitmap, rotation: Int, config: CaptureConfiguration, capturedAt: Long): CapturePhoto {
        require(config.isValid && rotation in listOf(0, 90, 180, 270))
        var oriented: Bitmap = raw
        var scaled: Bitmap = raw
        try {
            oriented = if (rotation == 0) raw else Bitmap.createBitmap(raw, 0, 0, raw.width, raw.height,
                Matrix().apply { postRotate(rotation.toFloat()) }, true)
            val limit = config.maximumImageDimension
            val longEdge = maxOf(oriented.width, oriented.height)
            scaled = if (limit != null && longEdge > limit) {
                val ratio = limit.toDouble() / longEdge
                Bitmap.createScaledBitmap(oriented, maxOf(1, (oriented.width * ratio).roundToInt()),
                    maxOf(1, (oriented.height * ratio).roundToInt()), true)
            } else oriented
            val bytes = ByteArrayOutputStream().use {
                check(scaled.compress(Bitmap.CompressFormat.JPEG, (config.jpegQuality * 100).roundToInt(), it))
                it.toByteArray()
            }
            return CapturePhoto(bytes, scaled.width, scaled.height, capturedAt)
        } finally {
            if (scaled !== raw && scaled !== oriented) scaled.recycle()
            if (oriented !== raw) oriented.recycle()
        }
    }
}
