package com.skincapture.skin_capture

import android.content.Intent
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import android.view.ViewGroup
import android.widget.Button
import android.widget.TextView
import com.google.mlkit.common.MlKit
import com.google.mlkit.common.sdkinternal.MlKitContext
import java.io.File
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [28], qualifiers = "mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class CaptureInterfaceTest {
    @Before fun prepareMlKit() {
        // Robolectric 共用同一個 ML Kit singleton，不能在每個案例重複初始化。
        try { MlKitContext.getInstance() } catch (_: IllegalStateException) {
            MlKit.initialize(RuntimeEnvironment.getApplication())
        }
    }

    @Test fun `系統忽略直立鎖定時結束拍攝且回傳明確錯誤`() {
        val sessionId = CaptureSessions.create(CaptureConfiguration())
        val intent = Intent(RuntimeEnvironment.getApplication(), SkinCaptureActivity::class.java)
            .putExtra(SkinCaptureActivity.SESSION_ID, sessionId)
        val controller = Robolectric.buildActivity(SkinCaptureActivity::class.java, intent).create()
        try {
            controller.get().onConfigurationChanged(Configuration().apply {
                orientation = Configuration.ORIENTATION_LANDSCAPE
            })
            assertTrue(controller.get().isFinishing)
            assertEquals("unsupported_device", CaptureSessions.get(sessionId)!!.outcome!!.code)
        } finally { controller.destroy(); CaptureSessions.remove(sessionId) }
    }

    @Test fun `三種手機尺寸可顯示提示狀態與取消按鈕`() {
        for ((width, height) in listOf(360 to 640, 393 to 852, 480 to 960)) {
            val sessionId = CaptureSessions.create(CaptureConfiguration())
            val intent = Intent(RuntimeEnvironment.getApplication(), SkinCaptureActivity::class.java)
                .putExtra(SkinCaptureActivity.SESSION_ID, sessionId)
            // 只建立 UI，不啟動相機；黑色預覽不能代表真實相機驗證。
            val controller = Robolectric.buildActivity(SkinCaptureActivity::class.java, intent).create()
            try {
                val root = controller.get().findViewById<ViewGroup>(android.R.id.content).getChildAt(0)
                root.measure(View.MeasureSpec.makeMeasureSpec(width, View.MeasureSpec.EXACTLY),
                    View.MeasureSpec.makeMeasureSpec(height, View.MeasureSpec.EXACTLY))
                root.layout(0, 0, width, height)
                fun descendants(view: View): List<View> = listOf(view) + if (view is ViewGroup) {
                    (0 until view.childCount).flatMap { descendants(view.getChildAt(it)) }
                } else emptyList()
                val views = descendants(root)
                val cancel = views.filterIsInstance<Button>().single { it.text == "取消" }
                assertTrue(cancel.top >= 0 && cancel.bottom <= height)
                assertTrue(views.filterIsInstance<TextView>().any { it.text.contains("請將臉部放入框內") })
                assertEquals(3, views.filterIsInstance<TextView>().count { it.text.contains("待辨識") })
                assertTrue(views.filterIsInstance<CapturePreviewView>().single().height >= 200)
                val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                root.draw(Canvas(bitmap))
                val directory = File(requireNotNull(System.getProperty("skinCapture.previewDir")))
                directory.mkdirs()
                File(directory, "capture-${width}x${height}.png").outputStream().use {
                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)
                }
                bitmap.recycle()
            } finally {
                controller.destroy()
                CaptureSessions.remove(sessionId)
            }
        }
    }
}
