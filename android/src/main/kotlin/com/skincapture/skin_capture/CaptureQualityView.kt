package com.skincapture.skin_capture

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.Gravity
import android.view.View
import android.widget.LinearLayout
import android.widget.TextView
import java.util.Locale
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin

/** 與 iOS 狀態指示器相同的圖示，以 24 單位格線繪製，避免依賴系統圖示資源。 */
internal enum class QualityIcon { SUN, FACE, WIDTH }

internal class QualityIconView(context: Context, private val icon: QualityIcon) : View(context) {
    private val circle = Paint(Paint.ANTI_ALIAS_FLAG)
    private val stroke = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE; style = Paint.Style.STROKE
        strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND
    }
    private val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
    private val arc = RectF()
    private val arrows = Path()

    var circleColor: Int = UNKNOWN_COLOR
        set(value) { field = value; invalidate() }

    override fun onDraw(canvas: Canvas) {
        val size = min(width, height).toFloat()
        circle.color = circleColor
        canvas.drawCircle(width / 2f, height / 2f, size / 2f, circle)
        // 圖示占圓形一半，與 iOS 60pt 圓形內 30pt 圖示一致。
        val unit = size / 2f / 24f
        canvas.save()
        canvas.translate(width / 2f - 12 * unit, height / 2f - 12 * unit)
        canvas.scale(unit, unit)
        stroke.strokeWidth = 2f
        when (icon) {
            QualityIcon.SUN -> {
                canvas.drawCircle(12f, 12f, 4.5f, stroke)
                for (index in 0 until 8) {
                    val radians = Math.toRadians(index * 45.0)
                    val x = cos(radians).toFloat(); val y = sin(radians).toFloat()
                    canvas.drawLine(12 + x * 7.5f, 12 + y * 7.5f, 12 + x * 10.5f, 12 + y * 10.5f, stroke)
                }
            }
            QualityIcon.FACE -> {
                canvas.drawCircle(12f, 12f, 10f, stroke)
                canvas.drawCircle(8.5f, 9.5f, 1.4f, fill)
                canvas.drawCircle(15.5f, 9.5f, 1.4f, fill)
                arc.set(7.5f, 8.5f, 16.5f, 16.5f)
                canvas.drawArc(arc, 30f, 120f, false, stroke)
            }
            QualityIcon.WIDTH -> {
                canvas.drawLine(3f, 12f, 21f, 12f, stroke)
                arrows.reset()
                arrows.moveTo(7f, 8f); arrows.lineTo(3f, 12f); arrows.lineTo(7f, 16f)
                arrows.moveTo(17f, 8f); arrows.lineTo(21f, 12f); arrows.lineTo(17f, 16f)
                canvas.drawPath(arrows, stroke)
            }
        }
        canvas.restore()
    }

    companion object {
        val UNKNOWN_COLOR = Color.rgb(64, 64, 64)
        val PASSED_COLOR = Color.rgb(0, 204, 110)
        val FAILED_COLOR = Color.rgb(240, 71, 61)
    }
}

internal class CaptureQualityBadge(context: Context, private val name: String, icon: QualityIcon) :
    LinearLayout(context) {
    val iconView = QualityIconView(context, icon)
    val label = TextView(context)
    val statusLabel = TextView(context)
    var state = QualityState.UNKNOWN
        private set

    init {
        orientation = VERTICAL
        gravity = Gravity.CENTER_HORIZONTAL
        val density = resources.displayMetrics.density
        addView(iconView, LayoutParams((60 * density).toInt(), (60 * density).toInt()))
        label.apply {
            text = name; textSize = 15f; setTextColor(Color.WHITE); gravity = Gravity.CENTER; maxLines = 1
        }
        addView(label, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = (8 * density).toInt()
        })
        statusLabel.apply { textSize = 12f; setTextColor(Color.LTGRAY); gravity = Gravity.CENTER; maxLines = 1 }
        addView(statusLabel, LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.WRAP_CONTENT).apply {
            topMargin = (4 * density).toInt()
        })
        update(QualityState.UNKNOWN)
    }

    fun update(state: QualityState) {
        this.state = state
        val (color, status, spoken) = when (state) {
            QualityState.UNKNOWN -> Triple(QualityIconView.UNKNOWN_COLOR, "待辨識", "等待辨識")
            QualityState.PASSED -> Triple(QualityIconView.PASSED_COLOR, "符合", "符合")
            QualityState.FAILED -> Triple(QualityIconView.FAILED_COLOR, "需調整", "需要調整")
        }
        iconView.circleColor = color
        statusLabel.text = status
        contentDescription = "$name，$spoken"
    }

    /** 數字固定在角度欄，避免被距離、光線或倒數提示蓋掉。 */
    fun updateAngle(state: QualityState, yawDegrees: Double?, target: Double) {
        update(state)
        val targetText = String.format(Locale.US, "%+.0f", target)
        if (yawDegrees != null && yawDegrees.isFinite()) {
            val current = String.format(Locale.US, "%+.0f", yawDegrees)
            label.text = "臉角度 $current°"
            contentDescription = "$contentDescription，目前 $current 度，目標 $targetText 度"
        } else {
            label.text = name
            statusLabel.text = "角度待辨識"
            contentDescription = "$contentDescription，目前角度尚未辨識，目標 $targetText 度"
        }
    }
}

internal class CaptureQualityView(context: Context) : LinearLayout(context) {
    val lighting = CaptureQualityBadge(context, "光線", QualityIcon.SUN)
    val angle = CaptureQualityBadge(context, "臉角度", QualityIcon.FACE)
    val size = CaptureQualityBadge(context, "臉大小", QualityIcon.WIDTH)

    init {
        orientation = HORIZONTAL
        val spacing = (6 * resources.displayMetrics.density).toInt()
        setPadding(0, spacing, 0, spacing)
        listOf(lighting, angle, size).forEach {
            addView(it, LayoutParams(0, LayoutParams.WRAP_CONTENT, 1f).apply { setMargins(spacing, 0, spacing, 0) })
        }
    }

    fun update(quality: CaptureQuality, yawDegrees: Double?, targetYawDegrees: Double) {
        lighting.update(quality.lighting)
        angle.updateAngle(quality.angle, yawDegrees, targetYawDegrees)
        size.update(quality.size)
    }
}
