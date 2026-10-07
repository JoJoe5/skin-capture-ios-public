# App 團隊串接文件

## 介面與生命週期

本版串接環境為 Flutter 3.47.6 以上、iOS 16 以上、iPhone。CI 驗證版本固定為 Flutter 3.47.6；App 團隊若使用較舊 Flutter，需先提供版本並完成橋接適配與建置驗證。

Flutter 呼叫 `SkinCapture().capture(options: ...)`，SDK 以全螢幕原生畫面管理相機與確認流程。

| 結果 | Flutter 行為 |
|---|---|
| 使用者確認照片 | 回傳 `CaptureResult` |
| 使用者取消正常拍攝 | 回傳 `null` |
| 相機錯誤後取消 | 拋出 `SkinCaptureException`，包含原始錯誤碼 |
| 進行中再次呼叫 | 拋出 `capture_in_progress` |

回傳欄位為 `jpegBytes`、`width`、`height`、`mimeType`、`capturedAt`。`capturedAt` 為 UTC 拍攝時間。照片方向已烘焙到像素，EXIF orientation 為 1；輸出移除原始照片中繼資料，不裁切臉部。`maximumImageDimension == null` 保留原解析度；有設定則等比例縮小，不放大。

App 需自行處理登入憑證、API 上傳、上傳重試與資料保存。plugin 本身不含 HTTP 相依套件，以免綁定團隊網路架構；Demo 的 `example/lib/analysis/` 另以 `http` 套件示範上傳到 staging 測試端點並顯示報告，僅供參考，不屬於 SDK。上傳時依 API 要求指定 `image/jpeg` 與檔名，例如 `face.jpg`。

## 設定

0.1.3 尺寸參數改為 `minimumFaceHeight`／`maximumFaceHeight`。若原先自訂 `minimumFaceWidth`／`maximumFaceWidth`，需更新呼叫名稱並重新校正；寬度比例不能直接當作高度比例沿用。

| 參數 | 預設值 | 意義 |
|---|---:|---|
| minimumFaceHeight | 0.55 | 預覽臉框高度占橢圓引導框高度的下限 |
| maximumFaceHeight | 0.80 | 預覽臉框高度占橢圓引導框高度的上限 |
| centerTolerance | 0.16 | 臉框中心與目標中心的正規化偏移上限 |
| targetYawDegrees | 0 | 目標左右轉頭角度，單位為度，合法設定範圍 −60～60；0 為正面 |
| maximumAngle | 0.30 | yaw 與目標角度的偏差上限，以及 pitch／roll 的絕對上限；單位為弧度，預設約 17.2 度 |
| minimumBrightness | 50 / 255 | 臉部內縮區域平均 Y 亮度下限 |
| maximumBrightness | 170 / 255 | 平均 Y 亮度上限 |
| stableDuration | 0.6 秒 | 累積符合且臉框穩定的時間，短暫失效期間不計入 |
| countdownDuration | 1 秒 | 準備完成後倒數時間，短暫失效時暫停 |
| maximumImageDimension | null | 輸出長邊限制；可設 640～8192 |
| jpegQuality | 0.9 | JPEG 品質；可設 0.5～1，不能保證固定檔案大小 |
| accentColorArgb | 0xFF0DA185 | 原生畫面主色 |
| title／confirmText／retakeText | 繁體中文 | 標題與確認／重拍按鈕文字 |
| guidanceMessages | 空 map | 依引導狀態名稱覆寫提示文字 |

### 不同角度的拍攝檢核

`targetYawDegrees` 指定左右轉頭的目標；[Apple Vision yaw](https://developer.apple.com/documentation/vision/vnfaceobservation/yaw) 以弧度提供量測，SDK 將目標度數換算後，以 `abs(yaw - targetYawDegrees × π / 180) <= maximumAngle` 檢核。狀態燈與自動拍照使用同一判定；pitch（抬低頭）與 roll（歪頭）仍要求端正。預設目標 0 度維持原本正面拍攝行為。

例如，目標 45 度且容差 10 度，允許的 yaw 為 35～55 度；正面與相反方向不會通過：

```dart
import 'dart:math' as math;

final photo = await SkinCapture().capture(
  options: CaptureOptions(
    targetYawDegrees: 45,
    maximumAngle: 10 * math.pi / 180,
    title: '側臉拍攝',
  ),
);
```

`maximumAngle` 保留弧度介面，合法範圍 0.05～0.6。Demo 將容差轉成度數供調整；SDK 呼叫端需自行換算。只增加 `maximumAngle` 會放寬正面門檻，不會指定側臉；指定目標 45 度且沿用預設容差時，實際接受約 27.8～62.2 度。

目標正負沿用**非鏡像分析影像的 Vision yaw**，代表相反方向，不以自拍預覽的畫面左右命名。「左臉」需求定義為鏡頭拍到受拍者的左臉頰，與受拍者向左轉頭不同；須以實體 iPhone 的左右臉頰標記確認對應正負值，再設定 App 的左右臉按鈕。目前尚未實機驗證該對應，Demo 先標示 −45°／正面 0°／45°，角度未達標時顯示目前與目標度數。設定範圍不代表所有機型在側臉角度均能穩定辨識，Vision 量測為估計值。

每次呼叫仍只拍一張；多角度拍攝可由 App 分別呼叫並保存結果。低信心、角度缺失或僅有區域追蹤時仍禁止自動拍照。現有肌膚分析 API 的照片規格仍為單張正面照，側臉拍攝參數不等同後端已支援多角度分析。

中心目標為完整影像座標 `(0.5, 0.52)`，原點在左下。預覽橢圓依上方狀態列與底部提示間的空間等比例排版，寬高比為 0.8。0.1.4 起固定讓橢圓框高度對應完整影像高度的 75%，預覽依實際相機尺寸等比例呈現，縮放與距離門檻分開。`minimumFaceHeight`／`maximumFaceHeight` 表示臉框在預覽中的高度占橢圓高度的比例，預設 55～80%；換算為 Vision 完整影像座標的高度上下限為 `0.55 × 0.75 = 0.4125`、`0.80 × 0.75 = 0.60`。狀態燈與快門共用換算後的範圍，包含邊界；修改門檻不會改變預覽縮放。比例以偵測臉框為準，不以頭髮外緣計算。

0.1.3 的高度參數以完整影像為基準，升級 0.1.4 後改為橢圓框基準。若要維持某個原始影像門檻，可將原數值除以 0.75，並檢查是否在合法範圍；建議重新實機校正自訂值。Vision 量測、亮度取樣與輸出 JPEG 皆使用完整影像，不把預覽放大或橢圓裁切套用到照片。

| 狀態欄 | 判定方式 |
|---|---|
| 光線 | 臉部內縮區域的平均 Y 值在亮度上下限內 |
| 臉角度 | 姿態資料可靠、yaw 與目標的偏差及 pitch／roll 在門檻內，且臉部完整並位於置中容差內 |
| 臉大小 | 預覽臉框高度占橢圓引導框高度的比例在距離上下限內 |

三項門檻分開且同時量測，但共用臉部區域資料。符合為綠色「符合」、不符合為紅色「需調整」、無可用量測為灰色「待辨識」。姿態失效不清除仍可取得的光線與大小；臉部部分超出畫面時，光線仍可量測，角度與大小不合格。無臉部區域、多人或完全無效的臉框才會全部待辨識。大小不合格時，底部顯示「距離太遠／近一點」或「距離太近／遠一點」，不顯示高度術語或百分比。

偵測信心 0.3 以上的觀測可供 UI 顯示，姿態可靠性仍要求偵測信心至少 0.7。偵測短暫中斷時，可從上一張高信心單臉啟動 [Apple Vision 區域追蹤](https://developer.apple.com/documentation/vision/vntrackingrequest)，最多 2 秒且追蹤信心至少 0.5；追蹤位置供當下亮度與大小量測，角度為需調整，禁止倒數及快門。追蹤逾時、失敗、掉幀超過 0.5 秒、時間倒退、背景或重啟時清除，不沿用舊顏色；真正失去資料時提示「暫時無法辨識人臉」。這些信心值為初始設定，轉頭時的實際追蹤效果需 iPhone 驗收。

短暫失效的容錯期間也會顯示當下紅色與調整原因，不沿用舊的綠色。三項全綠後仍需穩定，底部顯示保持不動與倒數。圖示與版面參考使用者提供的畫面，判定門檻沿用本 SDK 的可調參數；未宣稱與參考 App 使用相同演算法。本版不提供語音按鈕。

每約 0.12 秒分析一次；臉框中心／寬度／高度變動容差為 0.05。位置、距離、角度、亮度或晃動失效時保留進度並暫停倒數，連續失效達 0.35 秒便歸零；失效原因改變不會重新取得容錯時間。恢復時若已超過容錯時間，也須重新穩定。無臉、多人、無效量測、相鄰分析間隔超過 0.5 秒或時間倒退時立即歸零。

暫停期間不累積穩定或倒數時間，快門必須有當下符合條件的結果才可拍攝；UI 與快門拒絕超過 0.5 秒的分析結果。光線門檻仍需實機校正，容錯只處理短暫波動。

引導狀態鍵：`noFace`、`multipleFaces`、`moveCloser`、`moveAway`、`centerFace`、`faceForward`、`moreLight`、`lessLight`、`holdStill`、`ready`。倒數與系統錯誤文字目前由 SDK 提供繁體中文。

### 角度量測狀態

0.1.8 起，當下角度固定顯示在「臉角度」欄，不受底部距離、光線或倒數提示影響。信心不足 0.7 的觀測若仍有有限 yaw，會顯示數字並標示「估計，待確認」，但不具備快門資格；原先 0.1.7 會隱藏這些數字。完全缺少 yaw、區域追蹤、多人、無效臉框或量測失效時顯示「角度待辨識」，清除舊值。底部將「角度尚未辨識」與「已量到但尚待確認」分開說明。這項修正不代表已提升 Vision 的側臉辨識成功率，需由實機的持續量測判斷。

### 預覽與成品鏡像確認

拍攝中的自拍預覽設為鏡像，Vision 分析及照片輸出設為不鏡像。照片依 EXIF 旋轉烘焙成正向像素，確認畫面與 Demo 首頁直接顯示同一份 JPEG，不另做左右翻轉。因此從預覽切到成品時，左右位置改變可能是正常現象；不能單靠與自拍預覽不同就判定成品鏡像。

實機驗證可拿印有「ABC 123」的紙入鏡，分別檢查拍完確認畫面、Demo 首頁及回傳 JPEG：預覽文字預期反轉，成品文字應可正常閱讀。同時記錄 TestFlight build、iPhone 型號與 iOS 版本，區分出錯階段。`PhotoProcessorTests` 增加左右色塊像素檢核，驗證不翻轉輸入的非鏡像影像；這只能驗證處理函式，仍需實機確認相機原始照片是否正確。

## 錯誤碼

| 錯誤碼 | 意義與建議 |
|---|---|
| permission_denied | 相機權限拒絕；SDK 提供開啟設定與重試 |
| camera_unavailable | 無可用前置相機；改用實體 iPhone |
| camera_interrupted | 相機中斷；SDK 提供重試 |
| analysis_failed | Vision 分析失敗；SDK 提供重試 |
| photo_failed | 拍照或 JPEG 轉換失敗；SDK 提供重試 |
| configuration_failed | 相機設定失敗 |
| invalid_configuration | 參數不合法；Dart 端通常先拋出 ArgumentError |
| missing_camera_usage_description | App 缺少相機用途說明 |
| capture_in_progress | 不可同時開啟兩個拍攝流程 |
| no_presenter／presentation_busy | Flutter 畫面尚未可顯示或正在切換 |
| unsupported_platform／unsupported_device | 非 iOS 或非 iPhone |
| plugin_unavailable | 未完成註冊或 plugin 已卸載 |
| invalid_result | 原生結果欄位缺失或不合法 |

## 原生串接

原生團隊可使用根目錄 Swift Package，或 CI 產出的 XCFramework，並建立 `SkinCaptureViewController(configuration:appearance:completion:)`。完成回呼在主執行緒執行一次；呼叫端應在回呼中關閉自己呈現的控制器。Flutter plugin 已處理關閉後回傳結果。

SDK 不自訂錄影、不要求麥克風或相簿權限。相機在 App 失去前景、完成拍照、取消或錯誤時停止；回到前景並符合畫面狀態時重新開始。
