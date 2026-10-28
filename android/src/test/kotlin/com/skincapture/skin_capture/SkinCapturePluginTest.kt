package com.skincapture.skin_capture

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.mockito.Mockito.*
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28])
class SkinCapturePluginTest {
    class HostActivity : Activity() {
        var request: Intent? = null
        var requestCode = 0
        @Suppress("DEPRECATION")
        override fun startActivityForResult(intent: Intent, code: Int) { request = intent; requestCode = code }
    }
    class Result : MethodChannel.Result {
        var completions = 0
        var value: Any? = null
        var code: String? = null
        override fun success(result: Any?) { completions++; value = result }
        override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) { completions++; code = errorCode }
        override fun notImplemented() { completions++; code = "not_implemented" }
    }
    private lateinit var host: HostActivity
    private lateinit var binding: ActivityPluginBinding
    private lateinit var plugin: SkinCapturePlugin
    @Before fun prepare() {
        host = Robolectric.buildActivity(HostActivity::class.java).setup().get()
        binding = mock(ActivityPluginBinding::class.java)
        `when`(binding.activity).thenReturn(host)
        plugin = SkinCapturePlugin().also { it.onAttachedToActivity(binding) }
    }
    @After fun cleanup() { plugin.onDetachedFromActivity(); host.finish() }
    private fun capture(result: Result = Result()): Result {
        plugin.onMethodCall(MethodCall("capture", emptyMap<String, Any>()), result)
        return result
    }
    private fun id() = host.request!!.getStringExtra(SkinCaptureActivity.SESSION_ID)!!

    @Test fun `照片不經 Intent 傳送且確認後只回傳一次`() {
        val result = capture()
        val sessionId = id()
        val photo = CapturePhoto(byteArrayOf(-1, -40, -1, -39), 800, 1000, 123L)
        CaptureSessions.get(sessionId)!!.outcome = CaptureOutcome(photo = photo)
        assertEquals(1, host.request!!.extras!!.size())
        assertTrue(plugin.onActivityResult(host.requestCode, Activity.RESULT_OK, null))
        assertEquals(photo.toMap(), result.value)
        assertNull(CaptureSessions.get(sessionId))
        assertFalse(plugin.onActivityResult(host.requestCode, Activity.RESULT_OK, null))
        assertEquals(1, result.completions)
    }

    @Test fun `取消與權限拒絕會釋放下一次拍攝`() {
        val cancelled = capture()
        CaptureSessions.get(id())!!.outcome = CaptureOutcome()
        plugin.onActivityResult(host.requestCode, Activity.RESULT_OK, null)
        assertNull(cancelled.value); assertNull(cancelled.code); assertEquals(1, cancelled.completions)
        val denied = capture()
        CaptureSessions.get(id())!!.outcome = CaptureOutcome(code = "permission_denied", message = "請允許相機")
        plugin.onActivityResult(host.requestCode, Activity.RESULT_OK, null)
        assertEquals("permission_denied", denied.code)
        assertEquals(0, capture().completions)
    }

    @Test fun `重複呼叫拒絕且配置重建保留等待中的結果`() {
        val first = capture()
        assertEquals("capture_in_progress", capture().code)
        plugin.onDetachedFromActivityForConfigChanges()
        assertEquals(0, first.completions)
        plugin.onReattachedToActivityForConfigChanges(binding)
        CaptureSessions.get(id())!!.outcome = CaptureOutcome()
        plugin.onActivityResult(host.requestCode, Activity.RESULT_OK, null)
        assertEquals(1, first.completions)
    }

    @Test fun `卸載畫面清除記憶體中的拍攝並回傳中斷`() {
        val result = capture()
        val sessionId = id()
        plugin.onDetachedFromActivity()
        assertEquals("camera_interrupted", result.code)
        assertNull(CaptureSessions.get(sessionId))
        assertEquals(1, result.completions)
    }

    @Test fun `不合法參數與缺少畫面不會啟動相機`() {
        val invalid = Result()
        plugin.onMethodCall(MethodCall("capture", mapOf("targetYawDegrees" to 61)), invalid)
        assertEquals("invalid_configuration", invalid.code)
        assertNull(host.request)
        plugin.onDetachedFromActivity()
        assertEquals("no_presenter", capture().code)
    }
}
