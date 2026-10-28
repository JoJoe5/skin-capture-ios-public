package com.skincapture.skin_capture

import java.nio.ByteBuffer
import org.junit.Assert.*
import org.junit.Test

class BrightnessAnalyzerTest {
    @Test fun `亮度取樣支援列尾填補像素步幅與四種旋轉`() {
        val width = 40; val height = 32; val stride = width * 2 + 7
        val bytes = ByteArray(stride * height) { 0 }
        for (y in 0 until height) for (x in 0 until width) bytes[y * stride + x * 2] = 100
        for (rotation in listOf(0, 90, 180, 270)) {
            assertEquals(100.0 / 255, BrightnessAnalyzer.meanLuma(ByteBuffer.wrap(bytes), width, height,
                stride, 2, rotation, FaceBounds(0.2, 0.2, 0.8, 0.8)), 1e-9)
        }
    }

    @Test fun `旋轉後臉框仍取樣感光元件的同一區域`() {
        val bytes = ByteArray(40 * 40)
        for (y in 0 until 40) for (x in 20 until 40) bytes[y * 40 + x] = 180.toByte()
        val boxes = listOf(
            0 to FaceBounds(0.6, 0.2, 0.9, 0.8),
            90 to FaceBounds(0.2, 0.6, 0.8, 0.9),
            180 to FaceBounds(0.1, 0.2, 0.4, 0.8),
            270 to FaceBounds(0.2, 0.1, 0.8, 0.4),
        )
        for ((rotation, box) in boxes) {
            assertEquals(180.0 / 255, BrightnessAnalyzer.meanLuma(ByteBuffer.wrap(bytes), 40, 40,
                40, 1, rotation, box), 1e-9)
        }
    }

    @Test fun `缺少影像資料與完全超出影像時不沿用亮度`() {
        assertTrue(BrightnessAnalyzer.meanLuma(ByteBuffer.allocate(1), 40, 40, 40, 1, 0,
            FaceBounds(0.2, 0.2, 0.8, 0.8)).isNaN())
        assertTrue(BrightnessAnalyzer.meanLuma(ByteBuffer.allocate(1600), 40, 40, 40, 1, 0,
            FaceBounds(2.0, 2.0, 3.0, 3.0)).isNaN())
    }
}
