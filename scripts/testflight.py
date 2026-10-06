"""在 macOS CI 匯入暫時簽章、建置 IPA，並依選項上傳 TestFlight。"""
import base64
import hashlib
import os
from pathlib import Path
import plistlib
import re
import secrets
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone


def run(command, label, *, env=None):
    # 例外只顯示步驟名稱，避免 subprocess 例外洩漏命令列中的憑證密碼。
    completed = subprocess.run(command, capture_output=True, env=env)
    if completed.returncode:
        raise RuntimeError(f"{label}失敗（代碼 {completed.returncode}）；請核對簽章設定")
    return completed.stdout


def main():
    required = ["APPLE_TEAM_ID", "APP_BUNDLE_ID", "IOS_DISTRIBUTION_P12_BASE64",
                "IOS_DISTRIBUTION_P12_PASSWORD", "IOS_APPSTORE_PROFILE_BASE64"]
    upload = os.environ.get("UPLOAD_TO_TESTFLIGHT") == "true"
    auth_method = os.environ.get("ASC_AUTH_METHOD", "api_key")
    if upload:
        if auth_method == "api_key":
            required += ["ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_PRIVATE_KEY_BASE64"]
        elif auth_method == "app_password":
            required += ["APPLE_ID", "APPLE_APP_SPECIFIC_PASSWORD"]
        else:
            raise RuntimeError("上傳認證方式不合法")
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError("尚未設定：" + "、".join(missing))
    build_number = os.environ.get("BUILD_NUMBER", os.environ.get("GITHUB_RUN_NUMBER", "1"))
    if not re.fullmatch(r"[1-9][0-9]*", build_number):
        raise RuntimeError("建置編號必須為正整數")
    team = os.environ["APPLE_TEAM_ID"]
    bundle = os.environ["APP_BUNDLE_ID"]
    if not re.fullmatch(r"[A-Z0-9]{10}", team):
        raise RuntimeError("APPLE_TEAM_ID 格式不合法")
    if not re.fullmatch(r"[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+", bundle):
        raise RuntimeError("APP_BUNDLE_ID 格式不合法")
    root = Path(__file__).resolve().parent.parent
    original_directory = Path.cwd()
    project = root / "example/ios/Runner.xcodeproj/project.pbxproj"
    original_project = None
    installed_profile = None
    keychain = None
    original_keychains = []
    with tempfile.TemporaryDirectory(prefix="skincapture-signing-") as directory:
        temporary = Path(directory)
        certificate = temporary / "distribution.p12"
        certificate.write_bytes(base64.b64decode(os.environ["IOS_DISTRIBUTION_P12_BASE64"], validate=True))
        profile_file = temporary / "app.mobileprovision"
        profile_file.write_bytes(base64.b64decode(os.environ["IOS_APPSTORE_PROFILE_BASE64"], validate=True))
        profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(profile_file)], "讀取描述檔"))
        entitlement = profile.get("Entitlements", {})
        if team not in profile.get("TeamIdentifier", []) or entitlement.get("application-identifier") != f"{team}.{bundle}":
            raise RuntimeError("描述檔的 Team ID 或 Bundle ID 不符合 Demo 設定")
        if entitlement.get("get-task-allow") or profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
            raise RuntimeError("請使用 App Store Connect 發佈描述檔")
        expiry = profile.get("ExpirationDate")
        if not expiry or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
            raise RuntimeError("描述檔已過期")
        profile_id = profile.get("UUID", "")
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", profile_id):
            raise RuntimeError("描述檔 UUID 不合法")
        original_keychains = re.findall(r'"([^"]+)"', run(["security", "list-keychains", "-d", "user"], "讀取鑰匙圈").decode())
        keychain_path = temporary / "build.keychain-db"
        try:
            password = secrets.token_hex(24)
            run(["security", "create-keychain", "-p", password, str(keychain_path)], "建立暫時鑰匙圈")
            keychain = keychain_path
            run(["security", "set-keychain-settings", "-lut", "21600", str(keychain)], "設定鑰匙圈")
            run(["security", "unlock-keychain", "-p", password, str(keychain)], "解鎖鑰匙圈")
            run(["security", "import", str(certificate), "-k", str(keychain), "-P",
                 os.environ["IOS_DISTRIBUTION_P12_PASSWORD"], "-T", "/usr/bin/codesign", "-T", "/usr/bin/security"], "匯入憑證")
            run(["security", "set-key-partition-list", "-S", "apple-tool:,apple:", "-s", "-k", password,
                 str(keychain)], "設定簽章工具存取")
            run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_keychains], "設定鑰匙圈搜尋")
            identities = run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)], "檢查發佈憑證").decode()
            accepted = {hashlib.sha1(der).hexdigest().upper() for der in profile.get("DeveloperCertificates", [])}
            available = set(re.findall(r"\b[A-Fa-f0-9]{40}\b", identities.upper()))
            if not accepted.intersection(available):
                raise RuntimeError("P12 缺少有效私鑰，或憑證與描述檔不相符")
            profile_folder = Path.home() / "Library/MobileDevice/Provisioning Profiles"
            profile_folder.mkdir(parents=True, exist_ok=True)
            installed_profile = profile_folder / f"{profile_id}.mobileprovision"
            if installed_profile.exists():
                installed_profile = None
                raise RuntimeError("暫時 runner 已有同名描述檔，請使用乾淨的建置環境")
            installed_profile.write_bytes(profile_file.read_bytes())

            text = project.read_text(encoding="utf-8")
            original_project = text
            text = text.replace("com.jojoe5.skincapture.demo", bundle)
            marker = "INFOPLIST_FILE = Runner/Info.plist;"
            if text.count(marker) != 3:
                raise RuntimeError("Demo 工程格式已變更，請更新簽章腳本")
            settings = (f'{marker}\n\t\t\t\tDEVELOPMENT_TEAM = {team};'
                        '\n\t\t\t\tCODE_SIGN_STYLE = Manual;'
                        '\n\t\t\t\tCODE_SIGN_IDENTITY = "Apple Distribution";'
                        f'\n\t\t\t\tPROVISIONING_PROFILE_SPECIFIER = "{profile_id}";')
            project.write_text(text.replace(marker, settings), encoding="utf-8")
            export_options = temporary / "ExportOptions.plist"
            export_options.write_bytes(plistlib.dumps({
                "method": "app-store-connect", "teamID": team, "signingStyle": "manual",
                "signingCertificate": "Apple Distribution", "provisioningProfiles": {bundle: profile_id},
                "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
            }))
            os.chdir(root / "example")
            # 完整擷取輸出；Flutter／Xcode 可能印出團隊、憑證與描述檔資訊。
            # 公開紀錄只顯示固定訊息，不依賴密碼遮罩過濾已解碼的公司資料。
            print("開始建置 Demo IPA。", flush=True)
            run(["flutter", "build", "ipa", "--release",
                 "--build-number", build_number,
                 "--export-options-plist", str(export_options)], "Demo IPA 建置")
            print("Demo IPA 建置完成。", flush=True)
            ipa_files = list((root / "example/build/ios/ipa").glob("*.ipa"))
            if len(ipa_files) != 1:
                raise RuntimeError("未找到唯一的 Demo IPA")
            if upload:
                command = ["xcrun", "altool", "--upload-app", "--type", "ios", "--file", str(ipa_files[0])]
                upload_env = dict(os.environ)
                if auth_method == "api_key":
                    key_id = os.environ["ASC_KEY_ID"]
                    if not re.fullmatch(r"[A-Z0-9]{10}", key_id):
                        raise RuntimeError("ASC_KEY_ID 格式不合法")
                    private_key = temporary / f"AuthKey_{key_id}.p8"
                    private_key.write_bytes(base64.b64decode(os.environ["ASC_PRIVATE_KEY_BASE64"], validate=True))
                    private_key.chmod(0o600)
                    upload_env["API_PRIVATE_KEYS_DIR"] = str(temporary)
                    command += ["--apiKey", key_id, "--apiIssuer", os.environ["ASC_ISSUER_ID"]]
                else:
                    # 不顯示命令列；錯誤只回傳步驟名稱，避免密碼出現在紀錄。
                    command += ["--username", os.environ["APPLE_ID"],
                                "--password", os.environ["APPLE_APP_SPECIFIC_PASSWORD"]]
                    if os.environ.get("ASC_PROVIDER"):
                        command += ["--asc-provider", os.environ["ASC_PROVIDER"]]
                run(command, "上傳 TestFlight", env=upload_env)
                print("Demo 已上傳 App Store Connect；請等待處理完成後加入 TestFlight 內部測試群組。")
            else:
                print("已完成簽章驗證，未啟用上傳；簽章產物將清除。")
        finally:
            os.chdir(original_directory)
            if original_project is not None:
                project.write_text(original_project, encoding="utf-8")
            if installed_profile is not None:
                installed_profile.unlink(missing_ok=True)
            if keychain is not None:
                subprocess.run(["security", "list-keychains", "-d", "user", "-s", *original_keychains], capture_output=True)
                subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True)
            # 不保留含有團隊識別、憑證或描述檔的簽章建置產物。
            signed_output = root / "example/build/ios"
            if signed_output.exists():
                build_directory = (root / "example/build").resolve()
                if not signed_output.resolve().is_relative_to(build_directory):
                    raise RuntimeError("簽章產物清理路徑不合法")
                shutil.rmtree(signed_output)


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        # 不輸出未知例外內容，避免 base64／私鑰或 subprocess 參數出現在紀錄。
        if isinstance(error, RuntimeError):
            print(str(error), file=sys.stderr)
        else:
            print("簽章設定或檔案格式不合法，請核對 Secrets。", file=sys.stderr)
        sys.exit(1)
