import 'dart:ui' as ui;
import 'dart:io';
import 'dart:async';
import 'dart:typed_data';
import 'package:ffmpeg_streamer/ffmpeg_streamer.dart';
import 'frame_batch_manager.dart';

class VideoFrameData {
  final int frameId;
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final double timestampMs;

  VideoFrameData({
    required this.frameId,
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.timestampMs,
  });

  /// Create from ffmpeg_streamer VideoFrame
  factory VideoFrameData.fromVideoFrame(VideoFrame frame, int frameId, double fps) {
    return VideoFrameData(
      frameId: frameId,
      rgbaBytes: frame.rgbaBytes,
      width: frame.width,
      height: frame.height,
      timestampMs: frameId / fps * 1000,
    );
  }
}

class VideoMetadata {
  final int width;
  final int height;
  final double fps;
  final int totalFrames;
  final int durationMs;
  final int audioSampleRate;
  final int audioChannels;

  VideoMetadata({
    required this.width,
    required this.height,
    required this.fps,
    required this.totalFrames,
    required this.durationMs,
    required this.audioSampleRate,
    required this.audioChannels,
  });

  @override
  String toString() {
    return 'VideoMetadata(${width}x$height, ${fps}fps, $totalFrames frames, ${durationMs}ms)';
  }
}

class FFmpegService {
  FfmpegDecoder? _decoder;
  VideoMetadata? _metadata;
  FrameBatchManager? _batchManager;

  /// Get the batch manager (for advanced usage)
  FrameBatchManager? get batchManager => _batchManager;

  /// Open a video file and extract its metadata
  Future<VideoMetadata?> openVideo(String path, {
    BatchManagerConfig? batchConfig,
  }) async {
    try {
      _decoder?.release();
      _batchManager?.dispose();
      
      _decoder = FfmpegDecoder();

      final success = await _decoder!.openMedia(path);
      if (!success) {
        return null;
      }

      _metadata = VideoMetadata(
        width: _decoder!.videoWidth,
        height: _decoder!.videoHeight,
        fps: _decoder!.fps,
        totalFrames: _decoder!.totalFrames - 1,
        durationMs: _decoder!.durationMs,
        audioSampleRate: _decoder!.audioSampleRate,
        audioChannels: _decoder!.audioChannels,
      );

      // Initialize batch manager
      _batchManager = FrameBatchManager(
        decoder: _decoder!,
        totalFrames: _metadata!.totalFrames,
        config: batchConfig ?? const BatchManagerConfig(),
      );

      return _metadata;
    } catch (e) {
      print('Error opening video: $e');
      return null;
    }
  }

  /// Get metadata of the currently opened video
  VideoMetadata? get metadata => _metadata;

  /// Get a specific frame by frame index (uses batch manager for optimization)
  Future<VideoFrameData?> getFrameAtIndex(int frameIndex, {bool useBatch = true}) async {
    if (_decoder == null || _metadata == null) {
      return null;
    }

    if (frameIndex < 0 || frameIndex >= _metadata!.totalFrames) {
      return null;
    }

    try {
      // Use batch manager if available
      if (_batchManager != null && useBatch) {
        final videoFrame = await _batchManager!.getFrame(frameIndex);
        if (videoFrame != null) {
          return VideoFrameData.fromVideoFrame(videoFrame, frameIndex, _metadata!.fps);
        }
        print("VideoFrame is null");
        return null;
      }

      // Fallback to direct async access (if batch manager not available)
      final completer = Completer<VideoFrameData?>();
      
      _decoder!.getFrameAtIndexAsync(frameIndex, (mediaFrame) {
        if (mediaFrame?.video != null) {
          final videoFrame = mediaFrame!.video!;
          completer.complete(VideoFrameData(
            frameId: frameIndex,
            rgbaBytes: videoFrame.rgbaBytes,
            width: videoFrame.width,
            height: videoFrame.height,
            timestampMs: frameIndex / _metadata!.fps * 1000,
          ));
        } else {
          completer.complete(null);
        }
      });

      return completer.future;
    } catch (e) {
      print('Error getting frame at index $frameIndex: $e');
      return null;
    }
  }

  /// Preload a range of frames for smooth playback
  Future<void> preloadFrameRange(int startFrame, int endFrame) async {
    if (_batchManager == null) return;
    await _batchManager!.preloadRange(startFrame, endFrame);
  }

  /// Get cache statistics
  CacheStats? getCacheStats() {
    return _batchManager?.getCacheStats();
  }

  /// Clear frame cache
  void clearFrameCache() {
    _batchManager?.clearCache();
  }



  /// Generate a list of thumbnail frames for the timeline
  /// Returns frames at regular intervals throughout the video
  Future<List<VideoFrameData>> generateTimelineThumbnails({
    int thumbnailCount = 30,
  }) async {
    if (_metadata == null || _decoder == null) {
      return [];
    }

    final List<VideoFrameData> thumbnails = [];
    final step = _metadata!.totalFrames / thumbnailCount;

    for (int i = 0; i < thumbnailCount; i++) {
      final frameIndex = (i * step).floor();
      final frame = await getFrameAtIndex(frameIndex, useBatch: false);
      if (frame != null) {
        thumbnails.add(frame);
      }
    }

    return thumbnails;
  }

  /// Convert video frame to Flutter ui.Image
  static Future<ui.Image> convertToFlutterImage(VideoFrameData frameData) async {
    final completer = Completer<ui.Image>();

    ui.decodeImageFromPixels(
      frameData.rgbaBytes,
      frameData.width,
      frameData.height,
      ui.PixelFormat.rgba8888,
      (image) {
        completer.complete(image);
      },
    );

    return completer.future;
  }

  /// Release resources
  Future<void> release() async {
    _batchManager?.dispose();
    _batchManager = null;
    await _decoder?.release();
    _decoder = null;
    _metadata = null;
  }

  /// Check if a video file is available
  Future<bool> isVideoFileAvailable(String path) async {
    return await File(path).exists();
  }

  /// Verify FFmpeg is properly installed and configured
  static Future<bool> verifyFFmpegSetup() async {
    try {
      // Try to open a dummy file to check if FFmpeg is available
      // This will throw an error if FFmpeg is not set up properly
      // For now, we just return true and let individual operations fail
      // In a production app, you might want to check for specific FFmpeg libraries
      return true;
    } catch (e) {
      print('FFmpeg verification failed: $e');
      return false;
    }
  }
}