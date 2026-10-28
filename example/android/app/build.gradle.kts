import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin 必須在 Android 與 Kotlin plugin 之後載入。
    id("dev.flutter.flutter-gradle-plugin")
}

// 上傳 Google Play 用的金鑰設定只存在本機，不提交至 git。
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use { load(it) }
    }
}

android {
    namespace = "com.jojoe5.skincapture.skin_capture_example"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Demo 以此識別碼發布至 Google Play 內部測試，上傳後不可變更；正式 App 由串接團隊設定。
        applicationId = "com.drwu.skincapture.demo"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 版本名稱與編號沿用 example/pubspec.yaml。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // 有本機上傳金鑰時用於 Google Play；否則以 debug 金鑰建置 Demo 供直接安裝驗證。
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("upload")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
