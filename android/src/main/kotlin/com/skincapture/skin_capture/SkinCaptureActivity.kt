package com.skincapture.skin_capture

import android.Manifest
import android.app.Activity
import android.app.AlertDialog
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.provider.Settings
import android.view.Gravity
import android.view.Surface
import android.view.WindowManager
import android.widget.Button
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.activity.OnBackPressedCallback
import androidx.activity.result.contract.ActivityResultContracts
import androidx.camera.core.AspectRatio
import androidx.camera.core.CameraState
import androidx.camera.core.CameraSelector
import androidx.camera.core.ExperimentalGetImage
import androidx.camera.core.ImageAnalysis
import androidx.camera.core.ImageCapture
import androidx.camera.core.ImageCaptureException
import androidx.camera.core.ImageProxy
import androidx.camera.core.Preview
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.core.content.ContextCompat
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import java.lang.ref.WeakReference
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.math.ceil

class SkinCaptureActivity : ComponentActivity() {
    private var session: CaptureSession? = null
    private lateinit var config: CaptureConfiguration
    private lateinit var evaluator: GuidanceEvaluator
    private val countdown = CaptureCountdown()
    private val handler = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val analyzing = AtomicBoolean(false)
    private val detector = FaceDetection.getClient(FaceDetectorOptions.Builder()
        .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_ACCURATE)
        .setMinFaceSize(0.10f).enableTracking().build())
    private var provider: ProcessCameraProvider? = null
    private var imageCapture: ImageCapture? = null
    private var imageAnalysis: ImageAnalysis? = null
    private var previewUseCase: Preview? = null
    private lateinit var root: LinearLayout
    private lateinit var guide: CapturePreviewView
    private lateinit var hint: TextView
    private lateinit var qualityView: CaptureQualityView
    private var foreground = false
    private var startingCamera = false
    private var takingPhoto = false
    private var completed = false
    private var error: CaptureOutcome? = null
    private var errorDialog: AlertDialog? = null
    private var photo: CapturePhoto? = null
    private var previewBitmap: Bitmap? = null
    @Volatile private var generation = 0
    @Volatile private var destroyed = false
    @Volatile private var lastFrameAt = Double.NEGATIVE_INFINITY
    private var lastAnalysisAt = Double.NEGATIVE_INFINITY
    private var evaluation = GuidanceEvaluation(Guidance.NO_FACE)

    private val permission = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (completed || destroyed) return@registerForActivityResult
        if (granted) startCamera() else showError("permission_denied", "請到設定允許此 App 使用相機")
    }

    private val freshnessCheck = object : Runnable {
        override fun run() {
            if (!foreground || completed || photo != null || error != null) return
            if (!takingPhoto && now() - lastAnalysisAt > 0.5) {
                evaluator.reset(); countdown.reset()
                evaluation = GuidanceEvaluation(Guidance.NO_FACE)
                renderEvaluation()
            } else if (!takingPhoto) renderEvaluation()
            handler.postDelayed(this, 100)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        session = CaptureSessions.get(intent.getStringExtra(SESSION_ID))
        val active = session
        if (active == null) { setResult(Activity.RESULT_CANCELED); finish(); return }
        active.activity = WeakReference(this)
        config = active.configuration
        evaluator = GuidanceEvaluator(config)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or WindowManager.LayoutParams.FLAG_SECURE)
        onBackPressedDispatcher.addCallback(this, object : OnBackPressedCallback(true) {
            override fun handleOnBackPressed() = complete(error ?: CaptureOutcome())
        })
        showCameraUi()
        if (resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE) {
            complete(CaptureOutcome(code = "unsupported_device", message = "拍攝僅支援直立畫面，請切換直立後重試"))
            return
        }
        // 無法延續重建前的相機、倒數或照片，明確結束讓呼叫端重新拍攝。
        if (savedInstanceState != null) complete(CaptureOutcome(code = "camera_interrupted", message = "拍攝畫面已重建，請重新拍攝"))
    }

    private fun showCameraUi() {
        root = column()
        root.addView(header(config.title))
        qualityView = CaptureQualityView(this)
        root.addView(qualityView)
        guide = CapturePreviewView(this, config.accentColorArgb)
        root.addView(guide, LinearLayout.LayoutParams(-1, 0, 1f))
        hint = label("請將臉部放入框內", 20f).apply { minHeight = dp(90) }
        root.addView(hint)
        root.addView(button("取消") { complete(error ?: CaptureOutcome()) })
        setContentView(root)
        renderEvaluation()
    }

    private fun column() = LinearLayout(this).apply {
        orientation = LinearLayout.VERTICAL
        setBackgroundColor(Color.BLACK)
        fitsSystemWindows = true
        setPadding(dp(12), dp(8), dp(12), dp(12))
    }
    private fun label(value: String, size: Float) = TextView(this).apply {
        text = value; textSize = size; setTextColor(Color.WHITE)
        gravity = Gravity.CENTER; setPadding(dp(4), dp(8), dp(4), dp(8))
    }
    private fun header(value: String): TextView = label(value, 22f)
    private fun button(value: String, action: () -> Unit) = Button(this).apply {
        text = value; isAllCaps = false; setTextColor(Color.WHITE)
        backgroundTintList = android.content.res.ColorStateList.valueOf(config.accentColorArgb)
        minHeight = dp(48); setOnClickListener { action() }
    }
    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()
    private fun now() = SystemClock.elapsedRealtimeNanos() / 1_000_000_000.0

    private fun ensurePermission() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
            startCamera()
        } else permission.launch(Manifest.permission.CAMERA)
    }

    @Suppress("DEPRECATION")
    private fun startCamera() {
        if (!foreground || completed || destroyed || takingPhoto || photo != null || error != null || startingCamera) return
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.CAMERA) != PackageManager.PERMISSION_GRANTED) return
        startingCamera = true
        val token = generation
        val future = ProcessCameraProvider.getInstance(this)
        future.addListener({
            startingCamera = false
            if (token != generation || destroyed || completed || !foreground || error != null) return@addListener
            try {
                val cameraProvider = future.get()
                provider = cameraProvider
                unbindCamera()
                if (!cameraProvider.hasCamera(CameraSelector.DEFAULT_FRONT_CAMERA)) {
                    showError("camera_unavailable", "此裝置無可用的前置相機，請使用實體 Android 手機")
                    return@addListener
                }
                val targetRotation = guide.display?.rotation ?: Surface.ROTATION_0
                val preview = Preview.Builder().setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .setTargetRotation(targetRotation).build()
                preview.setSurfaceProvider(guide.preview.surfaceProvider)
                val capture = ImageCapture.Builder().setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .setTargetRotation(targetRotation)
                    .setCaptureMode(ImageCapture.CAPTURE_MODE_MAXIMIZE_QUALITY).build()
                val analysis = ImageAnalysis.Builder().setTargetAspectRatio(AspectRatio.RATIO_4_3)
                    .setTargetRotation(targetRotation)
                    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST).build()
                imageCapture = capture; imageAnalysis = analysis; previewUseCase = preview
                analysis.setAnalyzer(worker) { analyze(it, token) }
                val camera = cameraProvider.bindToLifecycle(this, CameraSelector.DEFAULT_FRONT_CAMERA, preview, capture, analysis)
                camera.cameraInfo.cameraState.observe(this) { state ->
                    if (token == generation && foreground && photo == null && !completed && state.error != null) {
                        val code = if (state.error?.code == CameraState.ERROR_CAMERA_DISABLED) "permission_denied" else "camera_interrupted"
                        showError(code, "相機暫時無法使用，請檢查權限或稍後重試")
                    }
                }
                handler.removeCallbacks(freshnessCheck)
                handler.post(freshnessCheck)
            } catch (_: Exception) { showError("configuration_failed", "無法啟動相機，請稍後重試") }
        }, ContextCompat.getMainExecutor(this))
    }

    @androidx.annotation.OptIn(ExperimentalGetImage::class)
    private fun analyze(image: ImageProxy, token: Int) {
        val timestamp = now()
        if (destroyed || token != generation || timestamp - lastFrameAt < 0.12 || !analyzing.compareAndSet(false, true)) {
            image.close(); return
        }
        lastFrameAt = timestamp
        val mediaImage = image.image
        if (mediaImage == null) { analyzing.set(false); image.close(); return }
        val rotation = image.imageInfo.rotationDegrees
        val uprightWidth = if (rotation % 180 == 0) image.width else image.height
        val uprightHeight = if (rotation % 180 == 0) image.height else image.width
        try {
            detector.process(InputImage.fromMediaImage(mediaImage, rotation))
                .addOnSuccessListener(worker) { faces ->
                    try {
                        val measurements = faces.map { face ->
                            val box = face.boundingBox
                            val bounds = FaceBounds(box.left.toDouble() / uprightWidth, box.top.toDouble() / uprightHeight,
                                box.right.toDouble() / uprightWidth, box.bottom.toDouble() / uprightHeight)
                            FaceMeasurement(bounds, Math.toRadians(face.headEulerAngleY.toDouble()),
                                Math.toRadians(face.headEulerAngleX.toDouble()), Math.toRadians(face.headEulerAngleZ.toDouble()),
                                BrightnessAnalyzer.meanLuma(image, bounds))
                        }
                        handler.post {
                            if (token == generation && foreground && !completed && !takingPhoto && photo == null && error == null) {
                                guide.setImageSize(uprightWidth, uprightHeight)
                                acceptMeasurements(measurements, timestamp)
                            }
                        }
                    } catch (_: Exception) {
                        handler.post { if (token == generation && !destroyed) showError("analysis_failed", "無法讀取影像，請重試") }
                    } finally { releaseAnalysisImage(image) }
                }
                .addOnFailureListener(worker) {
                    releaseAnalysisImage(image)
                    handler.post {
                        if (token == generation && foreground && !completed && !destroyed) {
                            showError("analysis_failed", "無法辨識畫面，請重新啟動拍攝")
                        }
                    }
                }
                .addOnCanceledListener(worker) { releaseAnalysisImage(image) }
        } catch (_: Exception) {
            image.close(); analyzing.set(false)
            handler.post { if (token == generation && !destroyed) showError("analysis_failed", "無法辨識畫面，請重試") }
        }
    }

    private fun releaseAnalysisImage(image: ImageProxy) {
        image.close(); analyzing.set(false)
        if (destroyed) worker.shutdown()
    }

    private fun acceptMeasurements(faces: List<FaceMeasurement>, timestamp: Double) {
        if (now() - timestamp > 0.5) {
            evaluator.reset(); countdown.reset(); evaluation = GuidanceEvaluation(Guidance.NO_FACE)
            renderEvaluation(); return
        }
        lastAnalysisAt = timestamp
        evaluation = evaluator.evaluate(faces, timestamp)
        if (evaluation.guidance == Guidance.READY) {
            if (countdown.remaining(timestamp, config.countdownDuration) == null && evaluation.blockingGuidance == null) {
                countdown.setPaused(false, timestamp)
                if (countdown.remaining(timestamp, config.countdownDuration) == null) countdown.start(timestamp)
            }
            countdown.setPaused(!evaluation.canCapture, timestamp)
            val remaining = countdown.remaining(timestamp, config.countdownDuration)
            if (evaluation.canCapture && remaining != null && remaining <= 0 && now() - timestamp <= 0.5) takePhoto()
        } else countdown.reset()
        renderEvaluation()
    }

    private fun renderEvaluation() {
        if (!::qualityView.isInitialized || photo != null || error != null) return
        qualityView.update(evaluation.quality, evaluation.yawDegrees, config.targetYawDegrees)
        val reason = evaluation.blockingGuidance ?: evaluation.guidance
        val remaining = countdown.remaining(now(), config.countdownDuration)
        hint.text = when {
            takingPhoto -> "正在拍攝…"
            evaluation.canCapture && remaining != null -> "請保持不動\n${ceil(remaining).toInt().coerceAtLeast(1)}"
            else -> config.guidanceMessages[reason.key] ?: reason.message
        }
    }

    private fun takePhoto() {
        val capture = imageCapture ?: return
        if (takingPhoto || !foreground || completed) return
        takingPhoto = true
        val token = generation
        val capturedAt = System.currentTimeMillis()
        handler.removeCallbacks(freshnessCheck)
        capture.takePicture(worker, object : ImageCapture.OnImageCapturedCallback() {
            override fun onCaptureSuccess(image: ImageProxy) {
                try {
                    val result = PhotoProcessor.process(image, config, capturedAt)
                    handler.post {
                        if (token == generation && !destroyed && !completed && foreground) {
                            takingPhoto = false; photo = result; generation++
                            unbindCamera(); showConfirmation(result)
                        }
                    }
                } catch (_: Exception) {
                    handler.post { if (token == generation && !destroyed) showError("photo_failed", "照片轉換失敗，請重試") }
                } finally { image.close() }
            }
            override fun onError(exception: ImageCaptureException) {
                handler.post { if (token == generation && !destroyed) showError("photo_failed", "拍照失敗，請重試") }
            }
        })
    }

    private fun showConfirmation(result: CapturePhoto) {
        val content = column()
        content.addView(header("確認照片"))
        previewBitmap = BitmapFactory.decodeByteArray(result.bytes, 0, result.bytes.size)
        val image = ImageView(this).apply { scaleType = ImageView.ScaleType.FIT_CENTER; setImageBitmap(previewBitmap) }
        content.addView(image, LinearLayout.LayoutParams(-1, 0, 1f))
        content.addView(button(config.confirmText) { complete(CaptureOutcome(photo = result)) })
        content.addView(button(config.retakeText) {
            image.setImageDrawable(null); previewBitmap?.recycle(); previewBitmap = null
            photo = null; resetAnalysis(); showCameraUi(); ensurePermission()
        })
        content.addView(button("取消") { complete(CaptureOutcome()) })
        setContentView(content)
    }

    private fun showError(code: String, message: String) {
        if (completed || destroyed || errorDialog?.isShowing == true) return
        generation++; takingPhoto = false; startingCamera = false
        error = CaptureOutcome(code = code, message = message)
        handler.removeCallbacks(freshnessCheck); unbindCamera(); resetAnalysis()
        hint.text = message
        errorDialog = AlertDialog.Builder(this).setTitle("無法完成拍攝").setMessage(message)
            .setPositiveButton("重試") { _, _ -> error = null; errorDialog = null; ensurePermission() }
            .setNegativeButton("取消") { _, _ -> complete(error ?: CaptureOutcome()) }
            .apply {
                if (code == "permission_denied") setNeutralButton("開啟設定") { _, _ ->
                    errorDialog = null
                    startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                }
            }.setOnCancelListener { complete(error ?: CaptureOutcome()) }.show()
    }

    private fun resetAnalysis() {
        evaluator.reset(); countdown.reset()
        lastAnalysisAt = Double.NEGATIVE_INFINITY; lastFrameAt = Double.NEGATIVE_INFINITY
        evaluation = GuidanceEvaluation(Guidance.NO_FACE)
    }
    private fun unbindCamera() {
        imageAnalysis?.clearAnalyzer()
        val useCases = listOfNotNull(previewUseCase, imageCapture, imageAnalysis).toTypedArray()
        if (useCases.isNotEmpty()) provider?.unbind(*useCases)
        imageCapture = null; imageAnalysis = null; previewUseCase = null
    }
    private fun complete(outcome: CaptureOutcome) {
        if (completed) return
        completed = true; generation++
        session?.outcome = outcome
        handler.removeCallbacks(freshnessCheck); unbindCamera()
        setResult(Activity.RESULT_OK)
        finish()
    }

    override fun onResume() {
        super.onResume(); foreground = true
        if (session == null || completed) return
        if (error != null && errorDialog?.isShowing != true) {
            if (error?.code == "permission_denied" && checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED) {
                error = null; ensurePermission()
            } else showError(error!!.code!!, error!!.message!!)
        } else if (photo == null && error == null) ensurePermission()
    }
    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        // Android 16 的大螢幕可能忽略直立鎖定，不在不相符的方向使用舊分析。
        if (newConfig.orientation == Configuration.ORIENTATION_LANDSCAPE && session != null && !completed) {
            complete(CaptureOutcome(code = "unsupported_device", message = "拍攝僅支援直立畫面，請切換直立後重試"))
        }
    }
    override fun onPause() {
        foreground = false; generation++; startingCamera = false
        handler.removeCallbacks(freshnessCheck)
        if (::evaluator.isInitialized) resetAnalysis()
        if (takingPhoto && !completed) {
            takingPhoto = false
            complete(CaptureOutcome(code = "camera_interrupted", message = "拍照時離開了畫面，請重新拍攝"))
        }
        unbindCamera()
        super.onPause()
    }
    override fun onDestroy() {
        destroyed = true; generation++
        handler.removeCallbacksAndMessages(null)
        errorDialog?.dismiss(); errorDialog = null
        unbindCamera(); detector.close()
        if (!analyzing.get()) worker.shutdown()
        previewBitmap?.recycle(); previewBitmap = null; photo = null
        if (!completed) session?.outcome = CaptureOutcome(code = "camera_interrupted", message = "拍攝流程已中斷，請重新拍攝")
        session?.activity = null
        super.onDestroy()
    }

    companion object { internal const val SESSION_ID = "com.skincapture.sessionId" }
}
