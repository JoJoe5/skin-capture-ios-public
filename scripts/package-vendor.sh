#!/usr/bin/env bash
# 產生交付給廠商的 Flutter 套件 zip，只含 App 建置所需檔案與廠商串接指南。
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
version="$(sed -n 's/^version: //p' "$root/pubspec.yaml")"
out="$root/build/vendor"
stage="$out/skin_capture"
zip_path="$out/skin_capture-$version.zip"

if [ -n "$(git -C "$root" status --porcelain -- pubspec.yaml CHANGELOG.md lib ios android docs/VENDOR.md)" ]; then
  echo "交付內容有未提交的修改，請先提交再打包" >&2
  exit 1
fi

rm -rf "$out"
mkdir -p "$stage"

# 只取已提交內容，避免本機建置產物、金鑰或未提交修改混入交付包。
git -C "$root" archive HEAD \
  pubspec.yaml CHANGELOG.md lib \
  ios/skin_capture.podspec ios/skin_capture \
  android/build.gradle android/consumer-rules.pro android/src/main \
  | tar -x -C "$stage"
git -C "$root" show HEAD:docs/VENDOR.md > "$stage/README.md"

# 交付包不附原始碼 repository 位置；使用權由雙方合約約定，不附 LICENSE 檔。
sed -i '/^repository:/d' "$stage/pubspec.yaml"
sed -i \
  -e "s|s.license = .*|s.license = { :type => 'Proprietary' }|" \
  -e "s|s.homepage = .*|s.homepage = 'http://example.com'|" \
  -e "s|s.author = .*|s.author = { 'skin_capture' => 'email@example.com' }|" \
  "$stage/ios/skin_capture.podspec"

if grep -rqi "github" "$stage"; then
  echo "交付包仍含 GitHub 位置，請檢查" >&2
  exit 1
fi

# Windows 的 python3 可能只是商店捷徑，以實際能執行者為準。
py=""
for candidate in python3 python; do
  if "$candidate" -c "" > /dev/null 2>&1; then py="$candidate"; break; fi
done
[ -n "$py" ] || { echo "找不到 Python" >&2; exit 1; }

"$py" -I - "$out" "$zip_path" <<'PY'
import pathlib, sys, zipfile
out, zip_path = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as archive:
    for path in sorted((out / "skin_capture").rglob("*")):
        if path.is_file():
            archive.write(path, path.relative_to(out).as_posix())
PY

echo "$zip_path"
