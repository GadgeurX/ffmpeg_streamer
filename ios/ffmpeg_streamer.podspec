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
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'

  # FFmpeg Configuration
  # This assumes you are using a Pod that provides FFmpeg, OR you manually vend it.
  # For this template, we will allow 'GL-FFmpeg' or similar if available, OR
  # instruct the user to vend 'ffmpeg-kit-io' or similar.
  # But strictly following requirements to support manual linking:
  
  # Link against static libraries or frameworks if they exist in a known location
  # s.vendored_frameworks = 'Frameworks/ffmpeg.xcframework'
  # s.vendored_libraries = 'Libs/libavcodec.a', ...
  
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES', 
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/../src"',
    # 'LIBRARY_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Libs"'
  }
  s.swift_version = '5.0'
end
