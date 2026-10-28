# 專案規則

- 技術文件、程式註解與 git commit 使用繁體中文；commit 說明修改原因。
- iOS 原生 SDK 唯一來源在 `ios/skin_capture/Sources/SkinCaptureSDK`；Android 唯一來源在 `android/src/main/kotlin/com/skincapture/skin_capture`；不可另外複製一份給 Flutter。
- 支援 iPhone、iOS 16 以上與 Android 前置相機；Flutter Demo 最低 Android 7.0（API 24）。僅提供直立拍攝。SDK 不呼叫檢測 API、不上傳照片、不寫入相簿。
- Flutter 公開介面需處理成功、使用者取消、權限拒絕、拍攝中重複呼叫與平台不支援。
- iOS 相機設定與啟停在專用序列佇列；Vision 分析在另一個序列佇列；所有 UI 更新與完成通知在主執行緒。
- Android CameraX 綁定、啟停與 UI 在主執行緒；ML Kit、亮度取樣與 JPEG 轉換在背景執行。影像只能在取樣完成後關閉；過期結果與背景返回結果不能觸發快門。
- 變更後執行 `flutter analyze`、`flutter test` 與 Demo 測試；iOS 編譯、XCTest、XCFramework 封裝由 macOS CI 驗證。
- Android 變更需建置 Demo APK，執行 `:skin_capture:testDebugUnitTest` 與 `:skin_capture:lintDebug`；相機、鏡像及各機型門檻必須另做實機驗收。
- 不把憑證、描述檔、API 私鑰、照片或登入憑證放進 git。
