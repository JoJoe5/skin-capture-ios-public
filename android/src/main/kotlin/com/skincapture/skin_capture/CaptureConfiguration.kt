package com.skincapture.skin_capture

data class CaptureConfiguration(
    val minimumFaceHeight: Double = 0.55,
    val maximumFaceHeight: Double = 0.80,
    val centerTolerance: Double = 0.16,
    val maximumAngle: Double = 0.30,
    val targetYawDegrees: Double = 0.0,
    val minimumBrightness: Double = 50.0 / 255,
    val maximumBrightness: Double = 170.0 / 255,
    val stableDuration: Double = 0.6,
    val countdownDuration: Double = 1.0,
    val maximumImageDimension: Int? = null,
    val jpegQuality: Double = 0.9,
    val accentColorArgb: Int = 0xFF0DA185.toInt(),
    val title: String = "正臉拍攝",
    val confirmText: String = "使用這張照片",
    val retakeText: String = "重新拍攝",
    val guidanceMessages: Map<String, String> = emptyMap(),
) {
    val isValid: Boolean get() =
        minimumFaceHeight in 0.1..0.9 && maximumFaceHeight in 0.1..0.95 &&
        maximumFaceHeight > minimumFaceHeight && centerTolerance in 0.01..0.25 &&
        maximumAngle in 0.05..0.6 && targetYawDegrees in -60.0..60.0 &&
        minimumBrightness in 0.0..1.0 && maximumBrightness in 0.0..1.0 &&
        maximumBrightness > minimumBrightness && stableDuration in 0.2..5.0 &&
        countdownDuration in 1.0..5.0 && jpegQuality in 0.5..1.0 &&
        (maximumImageDimension == null || maximumImageDimension in 640..8192) &&
        title.isNotBlank() && confirmText.isNotBlank() && retakeText.isNotBlank()

    fun acceptsPose(yaw: Double, pitch: Double, roll: Double): Boolean {
        val limit = maximumAngle + 1e-12
        return listOf(yaw, pitch, roll).all { it.isFinite() } &&
            kotlin.math.abs(yaw - Math.toRadians(targetYawDegrees)) <= limit &&
            kotlin.math.abs(pitch) <= limit && kotlin.math.abs(roll) <= limit
    }

    companion object {
        fun fromMap(args: Map<*, *>): CaptureConfiguration {
            fun number(key: String, fallback: Double): Double =
                if (!args.containsKey(key)) fallback else (args[key] as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("$key 必須為數字")
            fun text(key: String, fallback: String): String =
                if (!args.containsKey(key)) fallback else args[key] as? String
                    ?: throw IllegalArgumentException("$key 必須為文字")
            val dimension = args["maximumImageDimension"]?.let {
                val value = (it as? Number)?.toDouble()
                    ?: throw IllegalArgumentException("照片尺寸必須為整數")
                require(value.isFinite() && value == value.toInt().toDouble())
                value.toInt()
            }
            val color = number("accentColorArgb", 0xFF0DA185.toLong().toDouble())
            require(color in 0.0..0xFFFFFFFF.toLong().toDouble() && color == color.toLong().toDouble())
            val messages = args["guidanceMessages"]?.let {
                require(it is Map<*, *> && it.all { (key, value) -> key is String && value is String })
                it.entries.associate { entry -> (entry.key as String) to (entry.value as String) }
            } ?: emptyMap()
            return CaptureConfiguration(
                number("minimumFaceHeight", 0.55), number("maximumFaceHeight", 0.80),
                number("centerTolerance", 0.16), number("maximumAngle", 0.30),
                number("targetYawDegrees", 0.0), number("minimumBrightness", 50.0 / 255),
                number("maximumBrightness", 170.0 / 255), number("stableDuration", 0.6),
                number("countdownDuration", 1.0), dimension, number("jpegQuality", 0.9),
                color.toLong().toInt(), text("title", "正臉拍攝"),
                text("confirmText", "使用這張照片"), text("retakeText", "重新拍攝"), messages,
            ).also { require(it.isValid) { "拍攝設定不合法" } }
        }
    }
}
