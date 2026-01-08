# ffmpeg_streamer

A **high-performance** Flutter plugin for using FFmpeg to decode video and audio frames via FFI. Now with **intelligent batch management** and a simplified high-level API!

## ✨ Features

### Version 0.4.0 - New! 🎉
- 🎯 **FFmpegService**: Simplified high-level API - no more manual decoder management
- 🧠 **Intelligent Batch Manager**: Automatic frame caching with smart preloading
- 📦 **7 Preset Configurations**: Optimized for different use cases (4K, editing, scrubbing, etc.)
- 🔧 **Auto-Configuration**: Automatically selects optimal settings based on video resolution
- 📊 **Real-time Cache Stats**: Monitor batches, frames, and memory usage
- 🎨 **35% Less Code**: Simplified example app demonstrates ease of use

### Version 0.3.0 Features
- 🚀 **Async API with Callbacks**: Non-blocking frame retrieval with native threading
- ⚡ **Ultra-Fast Batch Processing**: 87% faster for 100 frames (15s → 2s)
- 🧵 **Native Threading (pthread)**: Dedicated worker thread, zero UI blocking
- 📊 **Progress Tracking**: Real-time progress callbacks for batch operations
- 🔄 **Request Cancellation**: Cancel pending decode requests

### Core Features
- 🎥 **Video Decoding**: Access raw RGBA video frames
- 🔊 **Audio Decoding**: Access raw Float32 audio samples
- 📱 **Cross-Platform**: Android, iOS, macOS, Windows, Linux
- 🔙 **Backward Compatible**: All previous APIs still work

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

## 🚀 Quick Start

### 🌟 Recommended: High-Level API with FFmpegService

The easiest way to use ffmpeg_streamer with automatic batch management:

```dart
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';

void main() async {
  // Create service instance
  final service = FFmpegService();
  
  // Open video (batch manager is initialized automatically)
  final metadata = await service.openVideo('path/to/video.mp4');
  
  // Get video info
  print('Resolution: ${metadata!.width}x${metadata.height}');
  print('FPS: ${metadata.fps}');
  print('Total frames: ${metadata.totalFrames}');
  
  // Get a frame (uses intelligent batch caching automatically)
  final frameData = await service.getFrameAtIndex(42);
  if (frameData != null) {
    // Convert to Flutter image
    final image = await FFmpegService.convertToFlutterImage(frameData);
    displayImage(image);
  }
  
  // Check cache stats
  final stats = service.getCacheStats();
  print('Cache: ${stats?.cachedBatches} batches, ${stats?.totalFramesInCache} frames');
  
  // Cleanup
  await service.release();
}
```

### Advanced: Custom Batch Configuration

```dart
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';

void main() async {
  final service = FFmpegService();
  
  // Open with custom configuration for 4K video
  final metadata = await service.openVideo(
    'path/to/4k_video.mp4',
    batchConfig: BatchConfigPresets.video4K,
  );
  
  // Or use automatic configuration based on resolution
  final recommendedConfig = BatchConfigPresets.getRecommendedConfig(
    width: metadata!.width,
    height: metadata.height,
    totalFrames: metadata.totalFrames,
    availableMemoryMB: 2048,
  );
  
  // Preload a range for smooth playback
  await service.preloadFrameRange(0, 100);
  
  // Get frames with zero latency (already cached!)
  for (int i = 0; i < 100; i++) {
    final frame = await service.getFrameAtIndex(i);
    displayFrame(frame);
  }
}
```

### Available Batch Presets

```dart
// Standard - Balanced for most use cases (~1.25 GB for 1080p)
BatchConfigPresets.standard

// High Performance - Smooth playback (~2.5 GB for 1080p)
BatchConfigPresets.highPerformance

// Memory Efficient - Limited devices (~375 MB for 1080p)
BatchConfigPresets.memoryEfficient

// 4K Optimized - Large frames (~1.5 GB for 4K)
BatchConfigPresets.video4K

// Scrubbing - Timeline navigation (~2 GB for 1080p)
BatchConfigPresets.scrubbing

// Editing - Workflow optimized (~1.5 GB for 1080p)
BatchConfigPresets.editing

// Slow Motion - Frame analysis (~1 GB for 1080p)
BatchConfigPresets.slowMotion
```

### Low-Level API: Direct Decoder Access

For advanced users who need fine-grained control:

```dart
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';

void main() async {
  final decoder = FfmpegDecoder();
  
  // Open media file
  await decoder.openMedia('path/to/video.mp4');
  
  // Get media info
  print('Resolution: ${decoder.videoWidth}x${decoder.videoHeight}');
  print('FPS: ${decoder.fps}');
  print('Total frames: ${decoder.totalFrames}');
  
  // Get a single frame (sync)
  final frame = await decoder.getFrameAtIndex(42);
  if (frame?.video != null) {
    // Use frame.video.rgbaBytes (Uint8List)
    displayFrame(frame!.video!);
  }
  
  // Cleanup
  await decoder.dispose();
}
```

### 🔥 New Async API (Recommended for Performance)

```dart
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';

void main() async {
  final decoder = FfmpegDecoder();
  await decoder.openMedia('path/to/video.mp4');
  
  // Get a single frame with callback (async, non-blocking)
  decoder.getFrameAtIndexAsync(42, (frame) {
    if (frame?.video != null) {
      displayFrame(frame!.video!);
    }
  });
  
  // Get multiple frames - ULTRA FAST! (87% faster than loop)
  decoder.getFramesRangeByIndexAsync(
    0,  // start frame
    99, // end frame
    (frame) {
      // Called for EACH frame as it's decoded
      print('Received frame ${frame?.video?.frameId}');
      processFrame(frame);
    },
    progressCallback: (current, total) {
      // Real-time progress tracking
      print('Progress: ${(current/total*100).toInt()}%');
    },
  );
  
  await decoder.dispose();
}
```

### 📊 Performance Comparison

```dart
// ❌ OLD WAY (slow - 15 seconds for 100 frames)
for (int i = 0; i < 100; i++) {
  final frame = await decoder.getFrameAtIndex(i);
  processFrame(frame);
}

// ✅ NEW WAY (fast - 2 seconds for 100 frames!)
decoder.getFramesRangeByIndexAsync(0, 99, 
  (frame) => processFrame(frame)
);
```

### 🎬 Real-World Example: Video Player with Smooth Playback

```dart
class VideoPlayer {
  final FFmpegService _service = FFmpegService();
  VideoMetadata? _metadata;
  Timer? _playTimer;
  int _currentFrame = 0;
  
  Future<void> openVideo(String path) async {
    // Open with high performance preset for smooth playback
    _metadata = await _service.openVideo(
      path,
      batchConfig: BatchConfigPresets.highPerformance,
    );
    
    // Preload first batch for instant start
    await _service.preloadFrameRange(0, 90);
  }
  
  Future<void> play() async {
    final fps = _metadata!.fps;
    final frameDuration = Duration(milliseconds: (1000 / fps).round());
    
    _playTimer = Timer.periodic(frameDuration, (_) async {
      // Get frame (instant access from cache!)
      final frameData = await _service.getFrameAtIndex(_currentFrame);
      if (frameData != null) {
        final image = await FFmpegService.convertToFlutterImage(frameData);
        displayImage(image);
      }
      
      _currentFrame++;
      
      // Check cache stats
      final stats = _service.getCacheStats();
      print('Playing: frame $_currentFrame, cache: ${stats?.totalFramesInCache} frames');
    });
  }
  
  void dispose() {
    _playTimer?.cancel();
    _service.release();
  }
}
```

### 🖼️ Real-World Example: Timeline Thumbnails

```dart
Future<List<ui.Image>> generateTimelineThumbnails(String videoPath) async {
  final service = FFmpegService();
  
  // Open with scrubbing preset (optimized for random access)
  await service.openVideo(videoPath, batchConfig: BatchConfigPresets.scrubbing);
  
  // Generate thumbnails is built-in!
  final thumbnails = await service.generateTimelineThumbnails(thumbnailCount: 30);
  
  // Convert to Flutter images
  final images = <ui.Image>[];
  for (final thumbnail in thumbnails) {
    final image = await FFmpegService.convertToFlutterImage(thumbnail);
    images.add(image);
  }
  
  await service.release();
  return images;
}
```

## 📚 Documentation

- [Async API Guide](ASYNC_API_GUIDE.md) - Complete guide to async API
- [Migration Summary](MIGRATION_SUMMARY.md) - Migrating from v1.x to v2.0
- [Changelog](CHANGELOG_V2.md) - What's new in v2.0
- [Example App](example/lib/async_example.dart) - Full featured example

## 🧪 Testing Performance

Run the included performance test:

```bash
dart run test_async_perf.dart path/to/your/video.mp4
```

This will compare sync vs async performance and show you the improvements!

## License

This plugin code is licensed under the MIT License.
**FFmpeg** is licensed under LGPL or GPL. You are responsible for complying with the FFmpeg license in your final application.
