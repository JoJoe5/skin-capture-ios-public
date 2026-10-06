# 專案規則

- 技術文件、程式註解與 git commit 使用繁體中文；commit 說明修改原因。
- 原生 SDK 唯一來源在 `ios/skin_capture/Sources/SkinCaptureSDK`；不可複製一份給 Flutter。
- 僅支援 iPhone、iOS 16 以上、直立前置相機。SDK 不呼叫檢測 API、不上傳照片、不寫入相簿。
- Flutter 公開介面需處理成功、使用者取消、權限拒絕、拍攝中重複呼叫與平台不支援。
- 相機設定與啟停在專用序列佇列；Vision 分析在另一個序列佇列；所有 UI 更新與完成通知在主執行緒。
- 變更後執行 `flutter analyze`、`flutter test` 與 Demo 測試；iOS 編譯、XCTest、XCFramework 封裝由 macOS CI 驗證。
- 不把憑證、描述檔、API 私鑰、照片或登入憑證放進 git。
