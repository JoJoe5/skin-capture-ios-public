package com.skincapture.skin_capture

import android.app.Activity
import android.content.Intent
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.PluginRegistry

class SkinCapturePlugin : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
    PluginRegistry.ActivityResultListener {
    private var channel: MethodChannel? = null
    private var binding: ActivityPluginBinding? = null
    private var pendingResult: MethodChannel.Result? = null
    private var sessionId: String? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.skincapture/capture").also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method != "capture") { result.notImplemented(); return }
        if (pendingResult != null) { result.error("capture_in_progress", "已有拍攝流程進行中", null); return }
        val activity = binding?.activity
        if (activity == null || activity.isFinishing || activity.isDestroyed) {
            result.error("no_presenter", "找不到可顯示相機的 Flutter 畫面", null)
            return
        }
        val config = try {
            CaptureConfiguration.fromMap(call.arguments as? Map<*, *> ?: throw IllegalArgumentException())
        } catch (_: IllegalArgumentException) {
            result.error("invalid_configuration", "拍攝設定不合法", null)
            return
        }
        pendingResult = result
        sessionId = CaptureSessions.create(config)
        try {
            activity.startActivityForResult(Intent(activity, SkinCaptureActivity::class.java)
                .putExtra(SkinCaptureActivity.SESSION_ID, sessionId), REQUEST_CODE)
        } catch (_: RuntimeException) {
            complete(CaptureOutcome(code = "presentation_busy", message = "無法開啟拍攝畫面，請稍後重試"))
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE || pendingResult == null) return false
        val outcome = CaptureSessions.get(sessionId)?.outcome ?: if (resultCode == Activity.RESULT_CANCELED) {
            CaptureOutcome()
        } else CaptureOutcome(code = "camera_interrupted", message = "拍攝流程已中斷，請重新拍攝")
        complete(outcome)
        return true
    }

    private fun complete(outcome: CaptureOutcome) {
        val result = pendingResult
        pendingResult = null
        CaptureSessions.remove(sessionId)
        sessionId = null
        if (outcome.code != null) result?.error(outcome.code, outcome.message, null)
        else result?.success(outcome.photo?.toMap())
    }

    private fun abort() {
        CaptureSessions.get(sessionId)?.activity?.get()?.finish()
        complete(CaptureOutcome(code = "camera_interrupted", message = "Flutter 畫面已卸載，請重新拍攝"))
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addActivityResultListener(this)
    }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivityForConfigChanges() {
        binding?.removeActivityResultListener(this)
        binding = null
    }
    override fun onDetachedFromActivity() {
        abort()
        onDetachedFromActivityForConfigChanges()
    }
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        abort()
        channel?.setMethodCallHandler(null)
        channel = null
    }
    companion object { private const val REQUEST_CODE = 57481 }
}
