# Demo 安裝與 TestFlight 設定

公開 repo 為 `JoJoe5/skin-capture-ios-public`，已完成原始碼、建置紀錄及公開產物檢查。Demo 預設 Bundle ID 為 `com.jojoe5.skincapture.demo`，實際註冊資訊以 Secrets 提供，不寫入原始碼。

## 準備 App 與簽章

1. 登入 [Apple Developer 帳號](https://developer.apple.com/account)，選擇用於發佈 Demo 的團隊，註冊 Demo 專用 App ID。
2. 在 [App Store Connect](https://appstoreconnect.apple.com) 建立對應的 Demo App 紀錄。
3. 備妥 Apple Distribution 的 P12、匯出密碼及 App Store Connect 描述檔。單獨的 CER 不包含私鑰，不能取代 P12。
4. 準備 App 專用密碼，或 App Store Connect API 金鑰。簽章與上傳資料不貼到聊天、不放進 Git。

## 設定 Secrets

開啟 repo → Settings → Secrets and variables → Actions → Secrets。以下資料全部使用 Secrets；不要設為 Variables，避免步驟的環境變數列表顯示實際值。

| 名稱 | 用途 |
|---|---|
| APPLE_TEAM_ID | Apple Developer Team ID |
| APP_BUNDLE_ID | Demo 註冊的 Bundle ID；省略時採預設值 |
| IOS_DISTRIBUTION_P12_BASE64 | 發佈 P12 的 Base64 |
| IOS_DISTRIBUTION_P12_PASSWORD | P12 匯出密碼 |
| IOS_APPSTORE_PROFILE_BASE64 | App Store Connect 描述檔的 Base64 |
| APPLE_ID | 採 `app_password` 認證時使用的 Apple 帳號 |
| APPLE_APP_SPECIFIC_PASSWORD | 採 `app_password` 認證時使用的 App 專用密碼 |
| ASC_PROVIDER | 選填；帳號屬於多個發佈團隊時使用的 provider short name |
| ASC_KEY_ID | 採 `api_key` 認證時使用的 Key ID |
| ASC_ISSUER_ID | 採 `api_key` 認證時使用的 Issuer ID |
| ASC_PRIVATE_KEY_BASE64 | 採 `api_key` 認證時使用的 P8 私鑰 Base64 |

Base64 只是傳輸格式，不是加密。Windows 可用 `[Convert]::ToBase64String([IO.File]::ReadAllBytes('檔案絕對路徑'))` 準備值，直接填入 Secrets。

## 建置與手機安裝

1. 等 SDK 與 Flutter Demo 的一般 CI 通過。
2. 從 `main` 手動執行「Demo 簽章與 TestFlight」，選擇認證方式。
3. 指定 `build_number`；同一個版本再次上傳時要增加。新 repo 不應依賴重置後的工作流程流水號。
4. 關閉 `upload_to_testflight` 可驗證簽章；不提供 IPA 下載，結束後清除簽章產物。
5. 開啟 `upload_to_testflight` 才會上傳 App Store Connect。處理完成後，把版本加入 TestFlight 內部測試群組。
6. iPhone 安裝 TestFlight，接受邀請後安裝 Demo。

簽章流程只由原 repo 擁有人的 `main` 手動觸發。一般 CI 不取得簽章 Secrets，只產生未簽章 Demo、SDK 與測試畫面。

## 公開紀錄的範圍

簽章、Flutter IPA 建置與上傳的 stdout／stderr 全部由 Python 擷取，公開紀錄只保留固定步驟結果。建置失敗時只顯示步驟名稱與錯誤代碼；要追查詳細 Xcode 錯誤，請在私人環境重現。

TestFlight 流程不使用 `upload-artifact`。完成或失敗後還原工程，清除暫時描述檔、鑰匙圈與簽章建置目錄，避免產物包含團隊名稱、發佈憑證及描述檔。App Store Connect／TestFlight 仍會接收簽章 App；本流程只限制 GitHub 對外公開的資料。

macOS 15、Xcode 26.3 與 Flutter 3.47.6 沿用已驗證的建置工具；Demo 最低支援 iOS 16。

官方參考：[GitHub Secrets](https://docs.github.com/en/actions/reference/security/secrets)、[Flutter iOS 發佈](https://docs.flutter.dev/deployment/ios)、[Apple TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/)。
