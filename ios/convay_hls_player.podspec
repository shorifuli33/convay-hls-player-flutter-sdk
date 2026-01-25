Pod::Spec.new do |s|
  s.name             = 'convay_hls_player'
  s.version          = '0.1.0'
  s.summary          = 'Convay HLS player based on Better Player.'
  s.description      = <<-DESC
Advanced HLS player with token refresh and seamless playback.
  DESC
  s.homepage         = 'https://github.com/Synesis-IT-PLC/convay-hls-player-flutter-sdk'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Convay' => 'support@convay.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*.{h,m,swift}'
  s.dependency 'Flutter'
  s.dependency 'Cache'
  s.dependency 'HLSCachingReverseProxyServer'
  s.dependency 'GCDWebServer'
  s.dependency 'PINCache'
  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
end
