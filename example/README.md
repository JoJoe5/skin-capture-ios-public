# Flutter Demo

此 Demo 直接使用 `../` 的 `skin_capture` plugin。開啟 App 後選「開始拍攝」即可驗證引導、自動拍照、確認與 JPEG 回傳；右上角的「拍攝設定」提供亮度範圍調整。

需要實體 iPhone 與相機權限。GitHub Actions 的未簽章 iPhone App 不可直接安裝；請依根目錄的 `docs/TESTFLIGHT.md` 設定 TestFlight。

## 肌膚檢測 POC（staging 測試端點）

首頁的「呼叫檢測 API」開關預設關閉，此時只測試相機引導，照片不會離開手機，也看不到任何檢測入口。打開後，拍完照可按「送出肌膚檢測」（不會自動上傳），Demo 會把 SDK 回傳的 JPEG 上傳到 skin-analytics 專為 demo 提供的同步端點，並顯示報告（整體分數、摘要、六項分數與說明、本機照片）。SDK 本身不呼叫檢測 API，上傳與報告畫面只存在於 Demo（`lib/analysis/`）。

- 端點：`POST {檢測服務網址}/poc/skin-analysis`，multipart 只有 `front`（`image/jpeg`），不需登入與輪詢；回應通常 10～17 秒，客戶端逾時 90 秒。
- 連線設定：右上角雲朵圖示輸入「檢測服務網址」與選填的「測試權杖」（`X-POC-Token`）；設定只存在記憶體。也可在執行時預填，網址與權杖不放進 git：
  `flutter run --dart-define=SKIN_API_BASE_URL=https://…/skin-analytics --dart-define=POC_TOKEN=…`
- 錯誤處理：`PHOTO_REJECTED`（含多張臉）提示重拍；`ANALYSIS_UNAVAILABLE` 只顯示原因；`INVALID_MODEL_OUTPUT`、429、503 與斷線可重試；401 提示檢查權杖；404 表示端點尚未啟用。
- `api_validation.ok` 為 false 時，報告上方會提醒這張照片在正式 API 可能被拒絕。
- 服務尚未啟用時，首頁的「預覽範例報告」可用規格範例資料檢視報告畫面。
