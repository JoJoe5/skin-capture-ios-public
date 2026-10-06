"""選擇 runner 上已安裝的 iPhone 模擬器，避免依賴固定機型名稱。"""
import json
import subprocess

inventory = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"]))
phones = [device for runtime, devices in inventory["devices"].items()
          if "iOS" in runtime for device in devices
          if device.get("isAvailable") and device["name"].startswith("iPhone")]
if not phones:
    raise SystemExit("runner 沒有可用的 iPhone 模擬器")
print(phones[0]["udid"])
