# ffmpeg_streamer

A robust Flutter plugin for using FFmpeg to decode video and audio frames via FFI. Support for Android, iOS, macOS, Windows, and Linux.

## Features

- 🎥 **Video Decoding**: Access raw RGBA video frames.
- 🔊 **Audio Decoding**: Access raw Float32 audio samples.
- 🚀 **Performance**: Uses native FFmpeg with background thread decoding.
- 📱 **Cross-Platform**: Ready for all major Flutter platforms.

## Prerequisites & Setup

**IMPORTANT**: This plugin requires FFmpeg binaries. You must provide them due to licensing and size.

### Android
1. Download Android-compatible FFmpeg `.so` libraries (e.g., from [FFmpegKit](https://github.com/tanersener/ffmpeg-kit) or build yourself).
2. Place them in your app's `android/source/main/jniLibs/<ABI>/` or configure the plugin `src/main/jniLibs`.
   Required libraries:
   - libavformat.so
   - libavcodec.so
   - libavutil.so
   - libswscale.so
   - libswresample.so

    Headers
     Place the FFmpeg include directories (libavcodec/, libavformat/, etc.) in:
     `android/src/main/cpp/include/`

    So you should have `android/src/main/cpp/include/libavcodec/avcodec.h`, etc.

### iOS & macOS
1. **iOS**: Add a Pod dependency on an FFmpeg package or vend `ffmpeg.xcframework` in your Podfile.
2. **macOS**: Ensure FFmpeg is installed via Homebrew (`brew install ffmpeg`) or linked in your `macos/Runner.xcodeproj`.
3. The plugin looks for headers in standard `/usr/local/include` or `/opt/homebrew/include` on macOS.

### Windows
1. Set `FFMPEG_ROOT` CMake variable or place FFmpeg headers/libs in `windows/ffmpeg`.
2. Ensure `avcodec-*.dll` etc. are in the same folder as your executable when running.

### Linux
1. Install development packages:
   ```bash
   sudo apt-get install libavcodec-dev libavformat-dev libavutil-dev libswscale-dev libswresample-dev
   ```

## Usage

```dart
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';

void playVideo(String path) async {
  final decoder = FfmpegDecoder();
  await decoder.open(FfmpegMediaSource.fromFile(path));

  // Get Info
  final info = await decoder.mediaInfo;
  print('Playing ${info.width}x${info.height} video');

  // Listen to Frames
  decoder.videoFrames.listen((frame) {
    // Render frame.rgbaBytes (width x height x 4)
  });
  
  decoder.audioFrames.listen((frame) {
    // Play frame.samples
  });

  await decoder.play();
}
```

## License

This plugin code is licensed under the MIT License.
**FFmpeg** is licensed under LGPL or GPL. You are responsible for complying with the FFmpeg license in your final application.
