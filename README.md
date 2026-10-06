# 肌膚拍攝引導 SDK

供 Flutter App 使用的 iPhone 正臉相機 SDK。提供原生拍攝 UI、位置／距離／姿勢／穩定度／基本亮度引導、自動拍照，以及使用者確認後的 JPEG 回傳。

## 第一版範圍

- iPhone、iOS 16 以上、直立、前置相機，每次正臉一張。
- 黑底、大橢圓相機預覽，上方同時呈現「光線、臉角度、臉大小」三項狀態，底部提供雙行調整提示；本版不提供語音。
- 三項合格且穩定 0.6 秒後，倒數 1 秒自動拍照。狀態顏色為綠色符合、紅色需調整、灰色等待辨識；角度欄也包含置中。
- 臉大小的預設合格範圍為偵測臉框在預覽中的高度占橢圓框高度 60～80%，包含上下限；低於 60% 提示靠近，高於 80% 提示遠離。
- 預覽縮放固定，不隨大小門檻變動；畫面以「近一點／遠一點」引導；回傳照片仍保留完整影像。
- 轉頭時保留可用觀測，偵測短暫中斷可追蹤區域最多 2 秒，光線與大小使用當下影像；姿態未確認前禁止拍照。灰燈附「待辨識」，與紅燈「需調整」分開說明。
- 輕微晃動容差為影像比例 0.05；位置、距離、角度或亮度短暫失效時暫停倒數，0.35 秒內恢復可接續。持續失效、無臉、多人或影像中斷時重新開始；暫停期間不拍照。
- 照片確認與重拍；只有確認後才回傳資料給 App。
- 相機預覽為自拍鏡像；輸出為正向、不鏡像的完整照片，不加入美肌與濾鏡。
- SDK 不上傳照片、不呼叫檢測 API、不寫入相簿。App 團隊負責接續上傳與檢測。
- Flutter plugin 同時提供 Swift Package Manager 描述與 CocoaPods podspec；CI 主要驗證 Flutter 3.47.6 的 SwiftPM 路徑。

## Flutter 快速串接

公開後，App 團隊可直接取得此 repo；使用與交付權利依專案授權條款。在 `pubspec.yaml` 加入：

本版最低 Flutter 版本為 3.47.6，使用該版本的 registrar 控制器介面，並已由 CI 驗證；iOS 最低版本為 16.0。較舊 Flutter 版本需先調整與驗證原生橋接，不能直接套用本版的相容性宣告。

```yaml
dependencies:
  skin_capture:
    git:
      url: git@github.com:JoJoe5/skin-capture-ios-public.git
      ref: main # 驗收後建議改固定版本標籤或 commit
```

在 iOS App 的 `Info.plist` 加入 `NSCameraUsageDescription`，並將 iOS 最低版本設為 16.0。若使用 CocoaPods，也將 `Podfile` 的 `platform :ios` 設為 `'16.0'`。

```dart
import 'package:skin_capture/skin_capture.dart';

final sdk = SkinCapture();
try {
  final photo = await sdk.capture(
    options: const CaptureOptions(
      title: '肌膚檢測拍攝',
      accentColorArgb: 0xFF0DA185,
      maximumImageDimension: 2048, // 範例；預設 null 保留相機解析度
      jpegQuality: 0.9,
    ),
  );
  if (photo == null) return; // 使用者取消
  // photo.jpegBytes 為 Uint8List，交由 App 的 HTTP 層上傳。
  // photo.mimeType = image/jpeg，photo.width／height 為實際像素尺寸。
  // 不需要先轉 Base64；依檢測 API 合約選用 multipart 或二進位 body。
} on SkinCaptureException catch (error) {
  // App 可依 error.code 處理錯誤，再顯示 error.message。
}
```

詳細設定與錯誤碼見 [串接文件](docs/INTEGRATION.md)。

## Demo 與建置

`example/` 是 Flutter Demo，直接使用根目錄的 plugin。macOS 開發環境可執行：

```bash
flutter pub get
cd example
flutter pub get
flutter run
```

拍攝需使用實體 iPhone；模擬器可驗證 App 啟動、Flutter 串接與無相機錯誤處理。Demo 首頁顯示目前臉大小範圍，點「調整」或右上「拍攝設定」可微調：

- 「臉在框內的大小」預設 60～80%，雙端滑桿可在 40～90% 內每次調整 1%。下限調小可離鏡頭更遠，上限調大允許靠得更近。
- 亮度上下限維持可調；大小或亮度下限不小於上限時，不能套用。
- 按「套用」後供下一次拍攝使用；關閉設定視窗不保存草稿。「恢復預設」還原大小與亮度，仍需按套用確認。
- 微調值保留在本次 App 開啟期間；重新啟動回到 SDK 預設值，預覽縮放不隨微調改變。

GitHub Actions 的 `ci.yml` 會執行 Flutter 靜態分析與測試、Swift 核心測試、iOS XCTest、iPhone 與模擬器 App 建置，並產出原生 `SkinCaptureSDK.xcframework.zip`。

模擬器啟動與截圖另設 5 分鐘上限；虛擬環境逾時時會保留警告，繼續上傳已完成編譯的 App。此情況不代表啟動檢查通過，實際拍攝仍需用 iPhone 驗收。

- `Demo-模擬器`：供 Mac 上的模擬器使用。
- `Demo-iPhone-待簽章`：驗證 iPhone 編譯，不可直接安裝到手機。
- `SkinCaptureSDK-XCFramework`：提供原生 App 團隊使用的 framework。
- `SDK-原生介面預覽`：XCTest 匯出的原生拍攝畫面，使用純色替代相機，供檢查三種 iPhone 尺寸的版面；不代表實機相機驗證。

TestFlight 安裝步驟與 CI 簽章設定見 [Demo 發佈文件](docs/TESTFLIGHT.md)。

## 亮度參考與限制

初始亮度範圍參考 [BioPass ID 官方套件文件](https://pub.dev/packages/biopassid_face_sdk) 的平均像素強度下限 50、上限 170。本專案實際計算的是 **完整範圍 YUV 影像中，臉框內縮 12% 區域的平均 Y 值除以 255**，因此 50／170 只作為具出處的初始參考，並不等同該 SDK 的判斷效果，也不是肌膚檢測的通用標準。

基本亮度引導無法完整判斷局部反光、左右陰影、白平衡偏色或環境照度。應用不同 iPhone、膚色與照明條件驗證；若檢測 API 提供拍攝規格，優先配合其規格調整。

## 原生 SDK 與測試

原生唯一來源位於 `ios/skin_capture/Sources/SkinCaptureSDK`。根目錄 `Package.swift` 供原生 SwiftPM 使用；Flutter 的 SwiftPM 與 CocoaPods 使用相同原始碼。

```bash
flutter analyze
flutter test
cd example && flutter test
```

在 macOS 執行 `swift test` 可驗證引導狀態；iOS 測試與封裝可用 XcodeGen 產生工程，詳見 CI。實機驗收案例見 [驗收文件](docs/ACCEPTANCE.md)。

## 公開與簽章資料

此副本的公開範圍與待完成驗證請見 [公開版本準備與驗收](docs/PUBLICATION_PLAN.md)。簽章流程不提供公開 IPA 下載；iPhone Demo 透過 TestFlight 安裝。
