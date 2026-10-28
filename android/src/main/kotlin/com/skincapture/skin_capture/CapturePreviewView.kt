package com.skincapture.skin_capture

import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.view.ViewGroup
import androidx.camera.view.PreviewView
import kotlin.math.min
import kotlin.math.roundToInt

internal class CapturePreviewView(context: Context, accent: Int) : ViewGroup(context) {
    val preview = PreviewView(context).apply {
        implementationMode = PreviewView.ImplementationMode.COMPATIBLE
        scaleType = PreviewView.ScaleType.FIT_CENTER
    }
    private val guide = RectF()
    private val clip = Path()
    private val border = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = accent; style = Paint.Style.STROKE; strokeWidth = 3 * resources.displayMetrics.density
    }
    private var imageRatio = 0.75

    init { setBackgroundColor(Color.BLACK); addView(preview); clipChildren = false }

    fun setImageSize(width: Int, height: Int) {
        val ratio = width.toDouble() / height
        if (ratio != imageRatio) { imageRatio = ratio; requestLayout() }
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val width = MeasureSpec.getSize(widthMeasureSpec)
        val height = MeasureSpec.getSize(heightMeasureSpec)
        setMeasuredDimension(width, height)
        val guideHeight = min(height * 0.94, width * 0.92 / 0.8)
        val guideWidth = guideHeight * 0.8
        guide.set(((width - guideWidth) / 2).toFloat(), ((height - guideHeight) / 2).toFloat(),
            ((width + guideWidth) / 2).toFloat(), ((height + guideHeight) / 2).toFloat())
        val imageHeight = (guideHeight / GUIDE_HEIGHT).roundToInt()
        preview.measure(MeasureSpec.makeMeasureSpec((imageHeight * imageRatio).roundToInt(), MeasureSpec.EXACTLY),
            MeasureSpec.makeMeasureSpec(imageHeight, MeasureSpec.EXACTLY))
    }

    override fun onLayout(changed: Boolean, left: Int, top: Int, right: Int, bottom: Int) {
        val x = ((width - preview.measuredWidth) / 2.0).roundToInt()
        val y = (guide.centerY() - preview.measuredHeight * 0.48).roundToInt()
        preview.layout(x, y, x + preview.measuredWidth, y + preview.measuredHeight)
        clip.reset(); clip.addOval(guide, Path.Direction.CW)
    }

    override fun dispatchDraw(canvas: Canvas) {
        val save = canvas.save()
        canvas.clipPath(clip)
        super.dispatchDraw(canvas)
        canvas.restoreToCount(save)
        canvas.drawOval(guide, border)
    }
}
