package com.skincapture.skin_capture

import org.junit.Assert.*
import org.junit.Test

class GuidanceEvaluatorTest {
    private val config = CaptureConfiguration()
    private val face = FaceMeasurement(FaceBounds(0.25, 0.23, 0.75, 0.73), 0.0, 0.0, 0.0, 0.4)
    private fun stable(evaluator: GuidanceEvaluator, start: Double = 0.0) {
        for (index in 0..7) evaluator.evaluate(listOf(face), start + index * 0.1)
    }

    @Test fun `穩定滿門檻才具備快門資格`() {
        val evaluator = GuidanceEvaluator(config)
        assertFalse(evaluator.evaluate(listOf(face), 0.0).canCapture)
        assertFalse(evaluator.evaluate(listOf(face), 0.3).canCapture)
        assertTrue(evaluator.evaluate(listOf(face), 0.6).canCapture)
    }

    @Test fun `光線角度與大小同時量測`() {
        val bad = face.copy(brightness = 0.9, yaw = 0.8,
            bounds = FaceBounds(0.35, 0.38, 0.65, 0.58))
        val result = GuidanceEvaluator(config).evaluate(listOf(bad), 0.0)
        assertEquals(CaptureQuality(QualityState.FAILED, QualityState.FAILED, QualityState.FAILED), result.quality)
        assertEquals(Guidance.MOVE_CLOSER, result.guidance)
    }

    @Test fun `角度大小與亮度包含上下限`() {
        for (height in listOf(config.minimumFaceHeight * GUIDE_HEIGHT, config.maximumFaceHeight * GUIDE_HEIGHT)) {
            val measured = face.copy(bounds = FaceBounds(0.25, 0.0, 0.75, height))
            assertEquals(QualityState.PASSED, CaptureQuality.measure(listOf(measured), config).size)
        }
        for (light in listOf(config.minimumBrightness, config.maximumBrightness)) {
            assertEquals(QualityState.PASSED, CaptureQuality.measure(listOf(face.copy(brightness = light)), config).lighting)
        }
        assertTrue(config.acceptsPose(config.maximumAngle, config.maximumAngle, -config.maximumAngle))
        assertFalse(config.acceptsPose(config.maximumAngle + 0.001, 0.0, 0.0))
    }

    @Test fun `左右目標角度拒絕正面與相反方向`() {
        for (target in listOf(-60.0, -45.0, 45.0, 60.0)) {
            val pose = config.copy(targetYawDegrees = target, maximumAngle = Math.toRadians(10.0))
            assertTrue(pose.acceptsPose(Math.toRadians(target + 10), 0.0, 0.0))
            assertTrue(pose.acceptsPose(Math.toRadians(target - 10), 0.0, 0.0))
            assertFalse(pose.acceptsPose(0.0, 0.0, 0.0))
            assertFalse(pose.acceptsPose(Math.toRadians(-target), 0.0, 0.0))
        }
    }

    @Test fun `短暫失效保留進度但禁止拍攝且不沿用綠燈`() {
        val evaluator = GuidanceEvaluator(config)
        stable(evaluator)
        val paused = evaluator.evaluate(listOf(face.copy(brightness = 0.9)), 0.8)
        assertEquals(Guidance.READY, paused.guidance)
        assertEquals(Guidance.LESS_LIGHT, paused.blockingGuidance)
        assertFalse(paused.canCapture)
        assertEquals(QualityState.FAILED, paused.quality.lighting)
        assertTrue(evaluator.evaluate(listOf(face), 1.0).canCapture)
    }

    @Test fun `失效原因改變不延長容錯期限`() {
        val evaluator = GuidanceEvaluator(config)
        stable(evaluator)
        evaluator.evaluate(listOf(face.copy(brightness = 0.9)), 0.8)
        evaluator.evaluate(listOf(face.copy(yaw = 0.8)), 1.0)
        val result = evaluator.evaluate(listOf(face), 1.2)
        assertEquals(0.0, result.progress, 1e-9)
        assertFalse(result.canCapture)
    }

    @Test fun `穩定進度排除失效期間`() {
        val evaluator = GuidanceEvaluator(config)
        evaluator.evaluate(listOf(face), 0.0)
        evaluator.evaluate(listOf(face), 0.2)
        evaluator.evaluate(listOf(face.copy(brightness = 0.9)), 0.3)
        val recovered = evaluator.evaluate(listOf(face), 0.5)
        assertEquals(0.5, recovered.progress, 1e-9)
        assertFalse(recovered.canCapture)
    }

    @Test fun `無臉多人不可靠姿態與掉幀立即歸零`() {
        for (faces in listOf(emptyList(), listOf(face, face), listOf(face.copy(poseReliable = false)),
            listOf(face.copy(yaw = Double.NaN)), listOf(face.copy(bounds = FaceBounds(-0.1, 0.1, 0.6, 0.7))))) {
            val evaluator = GuidanceEvaluator(config)
            stable(evaluator)
            assertFalse(evaluator.evaluate(faces, 0.8).canCapture)
            assertFalse(evaluator.evaluate(listOf(face), 0.9).canCapture)
        }
        for (timestamp in listOf(0.5, 1.3, Double.NaN)) {
            val evaluator = GuidanceEvaluator(config)
            stable(evaluator)
            assertFalse(evaluator.evaluate(listOf(face), timestamp).canCapture)
        }
    }

    @Test fun `角度未確認仍保留當下大小與亮度`() {
        val result = GuidanceEvaluator(config).evaluate(listOf(face.copy(poseReliable = false)), 0.0)
        assertEquals(QualityState.PASSED, result.quality.lighting)
        assertEquals(QualityState.PASSED, result.quality.size)
        assertEquals(QualityState.FAILED, result.quality.angle)
        assertEquals(0.0, result.yawDegrees!!, 0.0)
        assertFalse(result.canCapture)
    }

    @Test fun `倒數只累積符合條件的時間`() {
        val countdown = CaptureCountdown()
        countdown.start(0.0)
        assertEquals(0.6, countdown.remaining(0.4, 1.0)!!, 1e-9)
        countdown.setPaused(true, 0.4)
        countdown.setPaused(true, 0.5)
        assertNull(countdown.remaining(0.6, 1.0))
        countdown.setPaused(false, 0.7)
        assertEquals(0.6, countdown.remaining(0.7, 1.0)!!, 1e-9)
        assertEquals(0.0, countdown.remaining(1.3, 1.0)!!, 1e-9)
        countdown.reset()
        assertNull(countdown.remaining(1.5, 1.0))
    }

    @Test fun `原生拒絕非有限數值錯誤型別與不合法設定`() {
        for (args in listOf(mapOf("targetYawDegrees" to Double.NaN), mapOf("maximumAngle" to "大"),
            mapOf("maximumImageDimension" to 640.5), mapOf("accentColorArgb" to -1),
            mapOf("guidanceMessages" to mapOf("ready" to 1)), mapOf("title" to " "),
            mapOf("minimumBrightness" to 0.9, "maximumBrightness" to 0.1))) {
            assertThrows(IllegalArgumentException::class.java) { CaptureConfiguration.fromMap(args) }
        }
        assertTrue(CaptureConfiguration.fromMap(emptyMap<String, Any>()).isValid)
    }
}
