# 公開版本準備與驗收

## 公開版本

此副本從版本 0.1.5 的已追蹤檔案匯出，保留臉大小預設 60～80%、Demo 微調設定及目前 SDK 功能。公開 repo 為 `JoJoe5/skin-capture-ios-public`，使用新的初始提交，避免帶入舊的歷史與建置紀錄。

原有私人 repo 已建立本機 Git 歷史備份；待公開版建置與 TestFlight 上傳驗證後移除舊遠端。本 repo 不包含舊提交、舊 Actions 紀錄與已簽章 IPA；作者採 GitHub noreply 信箱。

## 對外資料

- SDK、Flutter 串接程式、拍攝門檻、Demo UI、測試與一般技術文件可被閱讀。
- 未簽章 Demo、XCFramework 及 CI 測試畫面可由 Actions 下載。
- Team ID、實際註冊資訊及上傳設定只從 Secrets 取得。
- 簽章與上傳工具的詳細輸出不公開，簽章 IPA 不產生公開下載產物。
- 套件授權仍採既有專有條款；公開原始碼不新增一般使用或再授權的權利。

## 驗證

1. 掃描所有公開檔案、初始提交與二進位資產，確認不包含實際公司名稱、網域、Team ID、憑證、描述檔、私鑰或照片。
2. 執行簽章隱私測試，驗證成功／失敗路徑都擷取工具輸出，還原工程並清除簽章產物。
3. 執行 Flutter 靜態分析、plugin 測試與 Demo 測試。
4. 公開後，先用不讀取簽章 Secrets 的一般 CI 驗證 macOS 建置與公開產物。
5. 通過檢查後才設定簽章 Secrets，執行 TestFlight 0.1.5 的建置 8；上傳後再確認公開紀錄與產物沒有團隊資料。

實際 macOS 簽章流程仍需新 repo 的 CI 驗證，本機測試使用模擬工具輸出，不能取代 Apple 簽章及上傳的實測。本機備份不推送至公開 repo。

## 本機驗證結果（2026-10-06）

- `flutter analyze`：通過。
- Flutter plugin 測試：7 項通過。
- Demo 測試：5 項通過。
- 簽章隱私測試：6 項通過，涵蓋成功、建置失敗、上傳失敗、只驗證簽章、API 金鑰與工作流程公開範圍。
- SDK 原生程式碼、Flutter 拍攝介面及 Demo 功能與原版本一致。
- 公開 repo 的 macOS CI 已通過：原生測試、XCFramework、Flutter 測試、模擬器及 iPhone 未簽章建置。
- 兩個 CI 工作的公開紀錄與 XCFramework 掃描未發現實際公司名稱、網域、Team ID 或私鑰。
- 真正的 TestFlight 上傳與舊遠端移除尚待完成。
