Pod::Spec.new do |s|
  s.name = 'skin_capture'
  s.version = '0.1.5'
  s.summary = 'iPhone 正臉相機拍攝引導與 JPEG 回傳。'
  s.description = '提供原生相機 UI、臉部姿勢與亮度引導、自動拍攝及 Flutter 串接介面。'
  s.homepage = 'https://github.com/JoJoe5/skin-capture-ios-public'
  s.license = { :type => 'Proprietary', :file => '../LICENSE' }
  s.author = { 'JoJoe5' => '57998286+JoJoe5@users.noreply.github.com' }
  s.source = { :path => '.' }
  s.source_files = 'skin_capture/Sources/**/*.swift'
  s.resource_bundles = { 'SkinCaptureSDK_privacy' => ['skin_capture/Sources/SkinCaptureSDK/PrivacyInfo.xcprivacy'] }
  s.dependency 'Flutter'
  s.platform = :ios, '16.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
