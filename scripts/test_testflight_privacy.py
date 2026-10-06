"""以模擬簽章工具驗證公開紀錄與產物清理，不使用真正的憑證。"""

import base64
import contextlib
from datetime import datetime, timedelta
import hashlib
import importlib.util
import io
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch


class TestFlightPrivacyTests(unittest.TestCase):
    def exercise(self, *, build_failure=False, upload_failure=False,
                 upload=True, authentication="app_password"):
        original_directory = Path.cwd()
        with tempfile.TemporaryDirectory(prefix="capture-privacy-test-") as directory:
            root = Path(directory)
            scripts = root / "scripts"
            scripts.mkdir()
            source = Path(__file__).with_name("testflight.py")
            script = scripts / "testflight.py"
            shutil.copyfile(source, script)
            spec = importlib.util.spec_from_file_location("signing_privacy_fixture", script)
            module = importlib.util.module_from_spec(spec)
            spec.loader.exec_module(module)
            project = root / "example/ios/Runner.xcodeproj/project.pbxproj"
            project.parent.mkdir(parents=True)
            original_project = "INFOPLIST_FILE = Runner/Info.plist;\n" * 3
            project.write_text(original_project, encoding="utf-8")
            certificate = b"unit-test-public-certificate"
            team = "A1B2C3D4E5"
            bundle = "com.example.capture"
            fingerprint = hashlib.sha1(certificate).hexdigest().upper()
            profile = {
                "TeamIdentifier": [team],
                "TeamName": "Example Organization",
                "Name": "Example Distribution Profile",
                "UUID": "12345678-1234-1234-1234-123456789ABC",
                "ExpirationDate": datetime.now() + timedelta(days=30),
                "DeveloperCertificates": [certificate],
                "Entitlements": {"application-identifier": f"{team}.{bundle}"},
            }
            environment = {
                "APPLE_TEAM_ID": team,
                "APP_BUNDLE_ID": bundle,
                "IOS_DISTRIBUTION_P12_BASE64": base64.b64encode(b"fixture-p12").decode(),
                "IOS_DISTRIBUTION_P12_PASSWORD": "fixture-password",
                "IOS_APPSTORE_PROFILE_BASE64": base64.b64encode(b"fixture-profile").decode(),
                "APPLE_ID": "fixture@example.invalid",
                "APPLE_APP_SPECIFIC_PASSWORD": "fixture-upload-password",
                "ASC_AUTH_METHOD": authentication,
                "ASC_KEY_ID": "Z9Y8X7W6V5",
                "ASC_ISSUER_ID": "fixture-issuer",
                "ASC_PRIVATE_KEY_BASE64": base64.b64encode(b"fixture-private-key").decode(),
                "UPLOAD_TO_TESTFLIGHT": str(upload).lower(),
                "BUILD_NUMBER": "8",
            }
            private_output = f"{team} {bundle} Example Organization fixture-password".encode()
            commands = []

            def fake_run(command, **kwargs):
                # 若移除擷取輸出，即使模擬工具不會真的洩漏，也必須使測試失敗。
                self.assertIs(kwargs.get("capture_output"), True)
                commands.append(command)
                output = private_output
                code = 0
                if command[:3] == ["security", "cms", "-D"]:
                    output = plistlib.dumps(profile)
                elif command[:2] == ["security", "list-keychains"]:
                    output = b'"/tmp/example-login.keychain-db"'
                elif command[:2] == ["security", "find-identity"]:
                    output = f'{fingerprint} "Example Organization"'.encode()
                elif command[:3] == ["flutter", "build", "ipa"]:
                    self.assertIn("8", command)
                    ipa = root / "example/build/ios/ipa/fixture.ipa"
                    ipa.parent.mkdir(parents=True)
                    ipa.write_bytes(b"fixture-signed-output")
                    code = 65 if build_failure else 0
                elif command[:3] == ["xcrun", "altool", "--upload-app"]:
                    code = 42 if upload_failure else 0
                    if authentication == "api_key":
                        self.assertIn("--apiKey", command)
                        self.assertTrue((Path(kwargs["env"]["API_PRIVATE_KEYS_DIR"])
                                         / "AuthKey_Z9Y8X7W6V5.p8").exists())
                    else:
                        self.assertIn("--username", command)
                return subprocess.CompletedProcess(command, code, output, private_output)

            output = io.StringIO()
            error = None
            with patch.dict(os.environ, environment, clear=True), \
                    patch.object(module.Path, "home", return_value=root / "home"), \
                    patch.object(module.subprocess, "run", side_effect=fake_run), \
                    contextlib.redirect_stdout(output), contextlib.redirect_stderr(output):
                try:
                    module.main()
                except RuntimeError as exception:
                    error = str(exception)
            transcript = output.getvalue() + (error or "")
            for value in (team, bundle, "Example Organization", "fixture-password",
                          "fixture-upload-password", "fixture@example.invalid",
                          "fixture-issuer", "Z9Y8X7W6V5"):
                self.assertNotIn(value, transcript)
            self.assertEqual(Path.cwd(), original_directory)
            self.assertEqual(project.read_text(encoding="utf-8"), original_project)
            self.assertFalse((root / "example/build/ios").exists())
            self.assertFalse(list((root / "home").rglob("*.mobileprovision")))
            self.assertTrue(any(c[:2] == ["security", "delete-keychain"] for c in commands))
            uploaded = any(c[:3] == ["xcrun", "altool", "--upload-app"] for c in commands)
            self.assertEqual(uploaded, upload and not build_failure)
            return transcript, error

    def test_success_keeps_only_fixed_messages_and_removes_signed_output(self):
        transcript, error = self.exercise()
        self.assertIsNone(error)
        self.assertIn("Demo 已上傳 App Store Connect", transcript)

    def test_build_failure_hides_tool_output_and_still_cleans_up(self):
        _, error = self.exercise(build_failure=True)
        self.assertIn("Demo IPA 建置失敗（代碼 65）", error)

    def test_upload_failure_hides_credentials_and_still_cleans_up(self):
        _, error = self.exercise(upload_failure=True)
        self.assertIn("上傳 TestFlight失敗（代碼 42）", error)

    def test_signing_validation_does_not_keep_downloadable_ipa(self):
        transcript, error = self.exercise(upload=False)
        self.assertIsNone(error)
        self.assertIn("簽章產物將清除", transcript)

    def test_api_key_upload_has_the_same_privacy_guarantees(self):
        _, error = self.exercise(authentication="api_key")
        self.assertIsNone(error)

    def test_workflow_does_not_publish_signed_artifacts_or_variable_values(self):
        workflow = Path(__file__).parent.parent / ".github/workflows/testflight.yml"
        text = workflow.read_text(encoding="utf-8")
        self.assertNotIn("upload-artifact", text)
        self.assertNotIn("vars.", text)
        for name in ("APPLE_TEAM_ID", "APP_BUNDLE_ID", "ASC_PROVIDER"):
            self.assertIn("secrets." + name, text)
        self.assertIn("refs/heads/main", text)
        self.assertIn("workflow_dispatch", text)


if __name__ == "__main__":
    unittest.main()
