# Android 串接與驗收

## 交付方式

iOS 與 Android 共用 `skin_capture` Flutter 套件、`CaptureOptions`、`SkinCapture().capture()` 與 `CaptureResult`。呼叫端不需要判斷平台；Flutter 自動選用 iOS 的 Swift 或 Android 的 Kotlin 實作。此 repository 名稱暫時保留 `skin-capture-ios-public`，未更動遠端 repository、套件名稱或 App 的 import。

兩個平台有各自的原生程式與相依套件，不能共用同一個二進位檔。iOS 原生團隊可使用既有 XCFramework；目前 Android 交付以 Flutter plugin 原始碼與可安裝 Demo APK 為主。Gradle 產生的 plugin AAR 包含 Flutter 橋接，不能當成已驗證的獨立純 Android SDK。若純原生 Android App 也需要串接，需另行拆分橋接與原生模組、定義原生公開介面並驗證 AAR。

## 環境與建置

- Flutter 3.47.6；Demo 使用 Android 7.0（API 24）以上與前置相機。
- plugin 原生最低 API 23；此 Flutter 版本的最低 API 為 24，Flutter App 以 24 為準。
- JDK 17、Android SDK 36、Build Tools 36.0.0、NDK 28.2.13676358。
- Demo 固定 Gradle 8.14.3、Android Gradle Plugin 8.11.1、Kotlin 2.2.20，便於重現建置。
- CameraX 1.4.2；ML Kit `com.google.mlkit:face-detection:16.1.7`，人臉模型隨 App 內建，拍攝不需要等待模型下載。

在 repository 根目錄執行：

```sh
flutter pub get
flutter analyze
flutter test
cd example
flutter pub get
flutter test
flutter build apk --debug
flutter run -d <Android裝置識別碼>
```

可安裝 APK 為 `example/build/app/outputs/flutter-apk/app-debug.apk`。Demo 識別碼為 `com.drwu.skincapture.demo`，已用於 Google Play 內部測試，不可再變更。

`example/android/key.properties` 存在時，release 建置使用其中的 Google Play 上傳金鑰；不存在時改用本機 debug 金鑰，僅供直接安裝 APK 驗證。金鑰與 `key.properties` 只存在本機，不提交至 git。`key.properties` 格式：

```properties
storeFile=<上傳金鑰 .jks 絕對路徑>
storePassword=<密碼>
keyAlias=upload
keyPassword=<密碼>
```

上傳 Google Play 時執行 `flutter build appbundle --release`，產出 `example/build/app/outputs/bundle/release/app-release.aab`。每次上傳前需提高 `example/pubspec.yaml` 的 `+` 後版本編號。

完成 Flutter Android 建置後，從 `example/android` 執行原生檢查：

```sh
./gradlew :skin_capture:testDebugUnitTest :skin_capture:lintDebug
```

Windows 使用 `./gradlew.bat`。Flutter 首次 Android 建置會準備 Gradle wrapper 與本機設定。測試報告在 `example/build/skin_capture/reports/`，CI 會保存報告與 APK。Robolectric 另在 `example/build/skin_capture/ui-preview/` 產生三種手機尺寸的原生 UI 預覽，以黑色替代相機，不代表相機實機驗證。

Windows 若遇到 Flutter analyzer 在中文路徑出現 LSP JSON 解析錯誤，可先將 repository 映射至未使用的磁碟代號，再從該路徑執行。例如 `subst S: "<repository絕對路徑>"`，執行完可用 `subst S: /D` 移除映射。此方式不搬移專案檔案。

## 2026-10-08 本機驗證

在 Windows 使用 Flutter 3.47.6、JDK 17 與上述 Android 工具鏈完成：

- Dart 格式與 `flutter analyze` 通過；Flutter 套件 10 項、Demo 39 項測試通過，Demo 平台變體包含 iOS 與 Android。
- `flutter build apk --debug` 通過，APK 包含 `armeabi-v7a`、`arm64-v8a`、`x86_64`；最低 API 24、目標 API 36，`apksigner verify` 通過。
- Kotlin／Robolectric 24 項測試通過，涵蓋引導邊界、暫停與重置、亮度旋轉取樣、JPEG 旋轉與縮放、plugin 結果／生命週期、三種手機尺寸及橫向中斷。
- Android Lint 為 0 錯誤、14 警告，主要為相依套件版本、固定方向、自訂 View 建構式、KTX 寫法與固定繁中 UI 的文字組合提示。Flutter 也提示目前固定的 Gradle／AGP／Kotlin 為支援版本下限，後續升級 Flutter 時需同步更新工具鏈。
- 已檢查 360×640、393×852、480×960 的原生畫面預覽。沒有連接 Android 實機，尚未驗證真實相機、左右臉頰對應或亮度門檻；iOS 原生編譯／XCTest 與新增 GitHub Actions job 尚未在本次工作執行。

## 權限與資料生命週期

plugin manifest 宣告 `CAMERA`、非必要的前置相機 feature 與不對外開放的直立拍攝 Activity，Flutter App 會自動合併。首次拍攝請求相機權限；拒絕時可重試、開啟設定或取消。拒絕後取消回傳 `permission_denied`；一般返回鍵與取消回傳 `null`。

拍攝只支援直立畫面。Android 16 的大螢幕可能忽略 Activity 直立鎖定；若系統仍以橫向顯示或在拍攝中切換橫向，SDK 停止並回傳 `unsupported_device`，提示切換直立後重新拍攝，避免使用方向不相符的影像。

plugin 本身只宣告相機權限，不要求麥克風或相簿，不上傳或儲存照片。ML Kit 的傳遞相依 Google Data Transport 會合併 `INTERNET` 與 `ACCESS_NETWORK_STATE` 權限；裝置端人臉偵測不需要將照片送到服務端，但不能據此宣稱第三方 SDK 完全沒有網路活動。Demo 為選用的檢測功能也宣告 `INTERNET`，開關預設關閉，上傳仍需按「送出肌膚檢測」。Android Demo 只使用 HTTPS；不開放全域明文 HTTP。

照片與結果存於程序記憶體，Intent 只帶一次拍攝的識別碼，避免 JPEG 超過 Binder 傳輸上限；確認後才經 Flutter channel 回傳。取消、重拍及 plugin 卸載清除持有的資料。拍攝 Activity 設定 `FLAG_SECURE`，避免系統截圖與最近使用畫面保存相機／照片。

離開前景立即停用相機並清除分析／倒數；正常回到前景重新辨識。快門處理途中離開畫面、非配置原因的 Flutter 畫面卸載、拍攝 Activity 重建會回傳 `camera_interrupted`。ML Kit 分析、Y 取樣與 JPEG 處理在背景執行，完成、UI 與 CameraX 綁定在主執行緒；舊世代或超過 0.5 秒的結果不能觸發快門。

## 對齊的功能與平台差異

| 項目 | Android 行為 |
|---|---|
| 拍攝流程 | 一次一張、直立前置相機、黑底橢圓預覽、三項狀態、提示、自動倒數、確認重拍 |
| 臉大小 | 預設占橢圓高度 55～80%；橢圓固定對應完整分析影像高度 75%，變更門檻不改變縮放 |
| 置中 | 正向影像左上為原點，目標 `(0.5, 0.48)`，對應 iOS 左下座標 `(0.5, 0.52)` |
| 姿態 | ML Kit Euler Y／X／Z 分別轉為 yaw／pitch／roll 弧度；目標 ±60 度、容差與 iOS 共用設定 |
| 亮度 | 正向臉框內縮 12%，轉回感光元件座標讀取 Y plane，考慮列尾填補與像素步幅；平均除以 255 |
| 穩定 | 預設 0.6 秒，中心／寬高每幀變動容差 0.05；倒數預設 1 秒 |
| 短暫失效 | 距離／中心／姿態／亮度／晃動失效可暫停最多 0.35 秒，不計入穩定與倒數時間；當下仍顯示失效狀態 |
| 無臉、多人或掉幀 | 立即重置；超過 0.5 秒的結果作廢，快門只由當下合格的分析觸發 |
| 照片 | CameraX 未鏡像完整照片，將旋轉烘焙至像素，重新編碼 JPEG 去除原始中繼資料；長邊只縮小不放大 |
| 錯誤與取消 | 共用 Flutter 錯誤碼、`null` 取消合約與重複呼叫防護 |

Android 使用 ML Kit 當下偵測，不實作 iOS Vision 最多 2 秒的失去偵測區域追蹤，也不假造 Vision 的信心分數。ML Kit 的 tracking ID 不表示失去人臉後仍有可用位置。無當下偵測即清除三項狀態與角度；偵測結果需有完整臉框、有限姿態及符合全部門檻才可拍照。

目標正負使用各平台非鏡像影像的估計角度；Apple Vision 與 ML Kit 的角度不能直接宣稱對應相同左右臉頰。App 若要提供「左臉／右臉」按鈕，需分平台實機校正。Android YUV 的亮度範圍與臉框也可能不同於 iOS；預設 50／255～170／255 是起始門檻，不能宣稱兩平台的光線判斷已等效。

API 串接與報告沿用 Flutter Demo；SDK 增加側臉功能不代表既有單張正面照分析 API 已支援側臉。

## 實機驗收

目前自動測試與建置無法替代真實相機。至少使用兩種不同品牌的 Android 手機，記錄機型、Android 版本、APK 版本與結果：

1. 首次允許、拒絕、永久拒絕與從設定允許後重試；返回鍵、取消後可再次呼叫，快速連按不開兩個相機。
2. 無臉、多人、靠近／遠離、置中、均勻光源及過暗／過亮時三項狀態與提示正確；小螢幕與系統導覽列不遮住按鈕。
3. 正面與 ±45 度各拍攝，記錄目前角度與左右臉頰；測試容差邊界、轉頭失去偵測、重新取得人臉與不同膚色。
4. 穩定後倒數、短暫偏離暫停、持續偏離重新倒數；多人、遮住鏡頭、掉幀與背景切換不得使用舊結果拍照。
5. 相機中進入背景後返回、快門時離開、其他 App 占用相機及權限撤銷，確認停止、重試及錯誤結果。
6. 印有「ABC 123」的紙入鏡：自拍預覽鏡像，確認頁、Demo 與輸出 JPEG 文字可正常閱讀；照片直立、完整且尺寸符合設定。
7. 重拍及確認只回傳最後一張照片；連續多次拍攝沒有相機占用或記憶體持續成長，SDK 沒有相簿檔案與照片上傳流量；第三方使用統計流量需分開觀察。
8. Demo API 開關關閉時不發出照片請求；開啟且按送出後依 staging 合約上傳，照片拒絕可重新拍攝。

## 官方參考

- [CameraX 影像轉換](https://developer.android.com/media/camera/camerax/transform-output)：區分影像 buffer、方向與預覽轉換。
- [ML Kit Android 人臉偵測](https://developers.google.com/ml-kit/vision/face-detection/android)：內建模型相依套件、輸入方向與姿態欄位。
- [CameraX ImageProxy](https://developer.android.com/reference/androidx/camera/core/ImageProxy)：影像取得、轉成 bitmap 與關閉生命週期。
