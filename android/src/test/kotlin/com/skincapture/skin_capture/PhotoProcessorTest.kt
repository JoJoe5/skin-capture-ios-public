package com.skincapture.skin_capture

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class PhotoProcessorTest {
    private fun image(width: Int = 800, height: Int = 1000) = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888).apply {
        for (y in 0 until height) for (x in 0 until width) setPixel(x, y, if (x < width / 2) Color.RED else Color.BLUE)
    }

    @Test fun `JPEG 保留完整尺寸與左右色塊且不鏡像`() {
        val raw = image()
        val result = PhotoProcessor.process(raw, 0, CaptureConfiguration(), 123L)
        assertEquals(800, result.width); assertEquals(1000, result.height)
        assertEquals(123L, result.capturedAt)
        assertEquals(255, result.bytes[0].toInt() and 255)
        assertEquals(216, result.bytes[1].toInt() and 255)
        val decoded = BitmapFactory.decodeByteArray(result.bytes, 0, result.bytes.size)
        assertTrue(Color.red(decoded.getPixel(100, 500)) > 200)
        assertTrue(Color.blue(decoded.getPixel(700, 500)) > 200)
        assertFalse(raw.isRecycled)
        raw.recycle(); decoded.recycle()
    }

    @Test fun `旋轉烘焙成像素並以正確尺寸回傳`() {
        for (rotation in listOf(90, 180, 270)) {
            val raw = image()
            val result = PhotoProcessor.process(raw, rotation, CaptureConfiguration(), 0L)
            assertEquals(if (rotation == 180) 800 else 1000, result.width)
            assertEquals(if (rotation == 180) 1000 else 800, result.height)
            val decoded = BitmapFactory.decodeByteArray(result.bytes, 0, result.bytes.size)
            val redPoint = when (rotation) { 90 -> 500 to 100; 180 -> 700 to 500; else -> 500 to 700 }
            val bluePoint = when (rotation) { 90 -> 500 to 700; 180 -> 100 to 500; else -> 500 to 100 }
            assertTrue(Color.red(decoded.getPixel(redPoint.first, redPoint.second)) > 200)
            assertTrue(Color.blue(decoded.getPixel(bluePoint.first, bluePoint.second)) > 200)
            raw.recycle(); decoded.recycle()
        }
    }

    @Test fun `輸出長邊只縮小不放大`() {
        for ((width, height) in listOf(800 to 1000, 400 to 500)) {
            val raw = image(width, height)
            val result = PhotoProcessor.process(raw, 0, CaptureConfiguration(maximumImageDimension = 640), 0L)
            assertEquals(if (width == 800) 512 else 400, result.width)
            assertEquals(if (height == 1000) 640 else 500, result.height)
            raw.recycle()
        }
    }
}
