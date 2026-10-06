#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/native
xcodegen generate --spec native-project.yml --project build/native
for destination in 'generic/platform=iOS' 'generic/platform=iOS Simulator'; do
  if [[ "$destination" == 'generic/platform=iOS' ]]; then slice=device; else slice=simulator; fi
  xcodebuild archive \
    -project build/native/SkinCaptureSDK.xcodeproj -scheme SkinCaptureSDK \
    -configuration Release -destination "$destination" \
    -archivePath "build/SkinCaptureSDK-$slice.xcarchive" \
    CODE_SIGNING_ALLOWED=NO SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES
done
xcodebuild -create-xcframework \
  -framework build/SkinCaptureSDK-device.xcarchive/Products/Library/Frameworks/SkinCaptureSDK.framework \
  -framework build/SkinCaptureSDK-simulator.xcarchive/Products/Library/Frameworks/SkinCaptureSDK.framework \
  -output build/SkinCaptureSDK.xcframework
ditto -c -k --sequesterRsrc --keepParent build/SkinCaptureSDK.xcframework build/SkinCaptureSDK.xcframework.zip
