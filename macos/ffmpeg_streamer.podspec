#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint ffmpeg_streamer.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'ffmpeg_streamer'
  s.version          = '0.0.1'
  s.summary          = 'A new Flutter project.'
  s.description      = <<-DESC
A new Flutter project.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  # This will ensure the source files in Classes/ are included in the native
  # builds of apps using this FFI plugin. Podspec does not support relative
  # paths, so Classes contains a forwarder C file that relatively imports
  # `../src/*` so that the C sources can be shared among all target platforms.
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*', '../src/**/*'
  s.public_header_files = 'Classes/**/*.h', '../src/**/*.h'
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '10.11'
  
  # FFmpeg Configuration (macOS)
  # This tries to link against Homebrew-installed FFmpeg or system FFmpeg.
  # User needs to ensure FFmpeg is installed (e.g., brew install ffmpeg).
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src" "/usr/local/include" "/opt/homebrew/include"',
    'LIBRARY_SEARCH_PATHS' => '"/usr/local/lib" "/opt/homebrew/lib"',
    'OTHER_LDFLAGS' => '-lavcodec -lavformat -lavutil -lswscale -lswresample'
  }
  s.swift_version = '5.0'
end
