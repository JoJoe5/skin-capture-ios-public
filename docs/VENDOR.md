# 廠商串接指南

本 SDK 是 Flutter 套件 `skin_capture`，同一套程式碼支援 iPhone 與 Android：開啟全螢幕原生相機畫面，引導使用者對準、在光線與角度合格後自動拍照，使用者確認後回傳 JPEG。SDK 不上傳照片、不呼叫檢測 API；拿到照片後由 App 自行上傳。

更完整的判定規則與平台差異見 [串接文件](INTEGRATION.md) 與 [Android 文件](ANDROID.md)。

## 環境需求

| 項目 | 需求 |
|---|---|
| Flutter | 3.47.6 以上（較舊版本請先告知，需另行驗證） |
| iOS | iPhone、iOS 16.0 以上 |
| Android | Android 7.0（API 24）以上、有前置相機；已驗證 JDK 17、compileSdk 36、AGP 8.11.1、Kotlin 2.2.20 |
| 畫面 | 只支援直立 |

## 安裝

`pubspec.yaml`：

```yaml
dependencies:
  skin_capture:
    git:
      url: https://github.com/JoJoe5/skin-capture-ios-public.git
      ref: <版本標籤> # 例如 v0.2.0，請固定使用交付時通知的標籤，不要用 main
```

iOS：

- `Info.plist` 加入 `NSCameraUsageDescription`，例如「拍攝臉部照片以進行肌膚檢測」。缺少時會拋出 `missing_camera_usage_description`。
- 最低版本設為 16.0；使用 CocoaPods 時 `Podfile` 的 `platform :ios` 也設為 `'16.0'`。

Android：

- `android/app/build.gradle(.kts)` 的 `minSdk` 設為 24 以上。
- 相機權限與拍攝畫面由套件自動合併，不需要手動修改 `AndroidManifest.xml`。

## 呼叫

```dart
import 'package:skin_capture/skin_capture.dart';

Future<void> takePhoto() async {
  try {
    final photo = await SkinCapture().capture(
      options: const CaptureOptions(
        title: '肌膚檢測拍攝',
        accentColorArgb: 0xFF0DA185,
      ),
    );
    if (photo == null) return; // 使用者取消
    // photo.jpegBytes：Uint8List，可直接上傳，不需要轉 Base64
    // photo.width／photo.height：實際像素；photo.mimeType：image/jpeg
    // photo.capturedAt：UTC 拍攝時間
  } on SkinCaptureException catch (error) {
    // 依 error.code 處理，見下方錯誤碼
  }
}
```

- 每次呼叫拍一張；同時只能有一個拍攝流程。
- 照片已轉正、不鏡像、不裁切、不加濾鏡，並移除原始中繼資料（EXIF、GPS 等）。
- 照片只存在記憶體，SDK 不寫入相簿或檔案。

## 可以調整的設定

| 參數 | 用途 |
|---|---|
| `accentColorArgb` | 主色（橢圓框、按鈕），格式 `0xAARRGGBB` |
| `title` | 拍攝畫面標題 |
| `confirmText`／`retakeText` | 確認、重拍按鈕文字 |
| `guidanceMessages` | 覆寫底部提示文字，鍵值見下表 |

| 鍵 | 預設提示 |
|---|---|
| `noFace` | 請將臉部放入框內 |
| `multipleFaces` | 畫面中請只保留一張臉 |
| `moveCloser` | 距離太遠，請靠近一點 |
| `moveAway` | 距離太近，請遠離一點 |
| `centerFace` | 請將臉部移到畫面中央 |
| `faceForward` | 請調整轉頭角度，保持頭部端正 |
| `moreLight` | 光線不足，請移到明亮且均勻的光源前 |
| `lessLight` | 光線太強，請避開直射光 |
| `holdStill` | 請保持不動 |
| `ready` | 準備完成，可以拍照 |

### 不建議修改的門檻

`minimumFaceHeight`、`maximumFaceHeight`、`centerTolerance`、`maximumAngle`、`targetYawDegrees`、`minimumBrightness`、`maximumBrightness`、`stableDuration`、`countdownDuration`、`maximumImageDimension`、`jpegQuality` 的預設值依肌膚檢測的照片需求設定。

這些參數雖然可以修改，但**請維持預設值**。放寬門檻（例如允許更暗或更遠）會讓使用者比較容易拍過，但送去檢測的照片品質下降，檢測結果會失準，且問題不易追查。若有拍攝困難的回報，請提供機型與情境給我們調整，而不是在 App 端放寬。

`targetYawDegrees`（側臉角度）尚未完成實機驗證，目前的檢測 API 也只接受正面照，請勿使用。

## 錯誤碼

使用者正常取消回傳 `null`，不是錯誤。相機、分析與拍照失敗時，SDK 會先在拍攝畫面提供重試；使用者放棄後才拋出例外。

| 錯誤碼 | 原因 | App 建議處理 |
|---|---|---|
| `permission_denied` | 使用者拒絕相機權限 | 說明用途並引導到系統設定開啟 |
| `camera_unavailable` | 沒有可用的前置相機 | 告知裝置不支援 |
| `camera_interrupted` | 相機被其他 App 占用或中斷 | 提示稍後重試 |
| `analysis_failed`／`photo_failed`／`configuration_failed` | 辨識、拍照或相機設定失敗 | 提示重試；持續發生請回報機型 |
| `unsupported_device` | iPad 等非 iPhone 裝置，或 Android 無法維持直立 | 告知裝置不支援或請切換直立 |
| `unsupported_platform` | 非 iOS／Android（例如 Web） | 不顯示拍攝入口 |
| `missing_camera_usage_description` | iOS 未設定相機用途說明 | 開發階段修正 `Info.plist` |
| `capture_in_progress` | 拍攝中重複呼叫 | 防止重複點擊 |
| `no_presenter`／`presentation_busy` | iOS 畫面尚未準備好或正在切換 | 稍後再呼叫 |
| `plugin_unavailable`／`invalid_result` | 套件未正確安裝或回傳資料異常 | 開發階段檢查安裝；正式環境回報 |
| `invalid_configuration` | 設定值超出範圍（Dart 端通常先拋出 `ArgumentError`） | 開發階段修正 |

## 上架隱私申報

SDK 本身：

- 只使用相機權限，不要求麥克風、相簿或位置。
- 人臉偵測在手機上執行；SDK 不上傳、不儲存照片，也不追蹤使用者。
- iOS 附隱私資訊檔（`PrivacyInfo.xcprivacy`）：不追蹤、不收集資料、不使用需申報理由的 API。
- Android 拍攝畫面禁止系統截圖與最近使用畫面預覽。

Android 使用的 Google ML Kit 會合併 `INTERNET` 與 `ACCESS_NETWORK_STATE` 權限。人臉偵測不會把照片送到伺服器，但 ML Kit 可能傳送使用統計與診斷資料給 Google；填寫 Google Play 資料安全表單時，請參考 [ML Kit 的資料揭露說明](https://developers.google.com/ml-kit/android-data-disclosure)。

App 上傳照片到檢測服務屬於 App 的行為，需由 App 自行申報。

## 已知限制

- 只支援直立、前置相機。
- 倒數、錯誤對話框與權限提示目前固定為繁體中文；底部引導提示可用 `guidanceMessages` 覆寫。
- 光線判斷為整臉平均亮度，無法完整判斷局部反光、陰影或偏色。
- 不偵測眼鏡、口罩等遮擋。

## 版本與回報

- 版本以 git 標籤發布，變更內容見 [CHANGELOG](../CHANGELOG.md)。升級前請閱讀該版本的變更說明。
- 回報問題時請提供 SDK 版本標籤、機型、系統版本、錯誤碼與重現步驟。
