package com.skincapture.skin_capture

import androidx.camera.core.ImageProxy
import java.nio.ByteBuffer
import kotlin.math.ceil
import kotlin.math.floor

internal object BrightnessAnalyzer {
    fun meanLuma(image: ImageProxy, face: FaceBounds): Double = meanLuma(
        image.planes[0].buffer.duplicate(), image.width, image.height,
        image.planes[0].rowStride, image.planes[0].pixelStride, image.imageInfo.rotationDegrees, face,
    )

    // 先將正向臉框轉回感光元件座標，再依 rowStride／pixelStride 讀取 Y plane。
    // Android YUV 的範圍可能因裝置而異；除以 255 是初始指標，需實機校正。
    fun meanLuma(buffer: ByteBuffer, width: Int, height: Int, rowStride: Int, pixelStride: Int,
                 rotation: Int, face: FaceBounds): Double {
        if (!face.valid || width <= 0 || height <= 0 || rowStride <= 0 || pixelStride <= 0) return Double.NaN
        val inner = FaceBounds(face.left + face.width * 0.12, face.top + face.height * 0.12,
            face.right - face.width * 0.12, face.bottom - face.height * 0.12)
        val raw = when (rotation) {
            0 -> inner
            90 -> FaceBounds(inner.top, 1 - inner.right, inner.bottom, 1 - inner.left)
            180 -> FaceBounds(1 - inner.right, 1 - inner.bottom, 1 - inner.left, 1 - inner.top)
            270 -> FaceBounds(1 - inner.bottom, inner.left, 1 - inner.top, inner.right)
            else -> return Double.NaN
        }
        if (!raw.intersects) return Double.NaN
        val left = floor(raw.left.coerceIn(0.0, 1.0) * width).toInt().coerceIn(0, width - 1)
        val right = ceil(raw.right.coerceIn(0.0, 1.0) * width).toInt().coerceIn(left + 1, width)
        val top = floor(raw.top.coerceIn(0.0, 1.0) * height).toInt().coerceIn(0, height - 1)
        val bottom = ceil(raw.bottom.coerceIn(0.0, 1.0) * height).toInt().coerceIn(top + 1, height)
        var sum = 0L
        var count = 0
        val offset = buffer.position()
        for (y in top until bottom step 4) for (x in left until right step 4) {
            val index = offset + y * rowStride + x * pixelStride
            if (index >= buffer.limit()) return Double.NaN
            sum += buffer.get(index).toInt() and 255
            count++
        }
        return if (count == 0) Double.NaN else sum.toDouble() / count / 255
    }
}
