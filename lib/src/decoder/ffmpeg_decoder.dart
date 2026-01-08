import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/lotterwise_ffmpeg_bindings.dart' as ffi_bindings;
import '../models/frame_data.dart';

/// FFmpeg-based decoder for media files.
/// Provides frame-by-frame access to both video and audio content.
class FfmpegDecoder {
  final ffi_bindings.LotterwiseFfmpegBindings _bindings;

  bool _isInitialized = false;
  bool _isOpened = false;

  int _durationMs = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;
  double _fps = 0;
  int _totalFrames = 0;
  int _currentFrameIndex = 0;

  int _audioSampleRate = 0;
  int _audioChannels = 0;

  /// Creates a new FFmpeg decoder instance.
  FfmpegDecoder() : _bindings = ffi_bindings.LotterwiseFfmpegBindings() {
    _initialize();
  }

  /// Initializes FFmpeg library.
  Future<void> _initialize() async {
    if (_isInitialized) return;

    _bindings.init();
    _isInitialized = true;
  }

  /// Opens a media file.
  ///
  /// Returns [true] if the file was opened successfully.
  Future<bool> openMedia(String filePath) async {
    if (!_isInitialized) {
      await _initialize();
    }

    // Close any previously opened media
    if (_isOpened) {
      await release();
    }

    final filePathC = filePath.toNativeUtf8();
    final result = _bindings.openMedia(filePathC.cast());
    calloc.free(filePathC);

    if (result == 0) {
      _isOpened = true;
      _loadMediaInfo();
      _currentFrameIndex = 0;
      return true;
    }

    return false;
  }

  /// Loads media information after opening a file.
  void _loadMediaInfo() {
    final mediaInfo = _bindings.getMediaInfo();
    _durationMs = mediaInfo.durationMs;
    _videoWidth = mediaInfo.width;
    _videoHeight = mediaInfo.height;
    _fps = mediaInfo.fps;
    _totalFrames = mediaInfo.totalFrames;
    _audioSampleRate = mediaInfo.audioSampleRate;
    _audioChannels = mediaInfo.audioChannels;
  }

  /// Returns the duration of the media in milliseconds.
  int get durationMs => _durationMs;

  /// Returns the video width.
  int get videoWidth => _videoWidth;

  /// Returns the video height.
  int get videoHeight => _videoHeight;

  /// Returns the video frame rate (frames per second).
  double get fps => _fps;

  /// Returns the total number of frames.
  /// May be 0 if the video doesn't provide this information.
  int get totalFrames => _totalFrames;

  /// Returns the audio sample rate (Hz).
  int get audioSampleRate => _audioSampleRate;

  /// Returns the number of audio channels.
  int get audioChannels => _audioChannels;

  /// Returns whether the media file has video.
  bool get hasVideo => _videoWidth > 0 && _videoHeight > 0;

  /// Returns whether the media file has audio.
  bool get hasAudio => _audioSampleRate > 0 && _audioChannels > 0;

  /// Returns the current frame index.
  int get currentFrameIndex => _currentFrameIndex;

  /// Retrieves a specific frame by its index.
  ///
  /// Returns a [MediaFrame] containing both video and audio data if available,
  /// or null if retrieval failed.
  /// The frame is automatically cached in memory - remember to free it.
  Future<MediaFrame?> getFrameAtIndex(int index) async {
    if (!_isOpened || index < 0) return null;

    // Get video frame
    final videoFramePtrPtr = calloc<Pointer<ffi_bindings.VideoFrame>>();
    VideoFrame? videoFrame;

    try {
      final videoResult = _bindings.getVideoFrameAtIndex(index, videoFramePtrPtr);
      if (videoResult >= 0 && videoFramePtrPtr.value != nullptr) {
        videoFrame = _convertAndFreeVideoFrame(videoFramePtrPtr.value);
        _currentFrameIndex = index;
      }
    } catch (e) {
      // Video retrieval failed
    } finally {
      calloc.free(videoFramePtrPtr);
    }

    // Get audio frame
    final audioFramePtrPtr = calloc<Pointer<ffi_bindings.AudioFrame>>();
    AudioFrame? audioFrame;

    try {
      final audioResult = _bindings.getAudioFrameAtIndex(index, audioFramePtrPtr);
      if (audioResult >= 0 && audioFramePtrPtr.value != nullptr) {
        audioFrame = _convertAndFreeAudioFrame(audioFramePtrPtr.value);
      }
    } catch (e) {
      // Audio retrieval failed
    } finally {
      calloc.free(audioFramePtrPtr);
    }

    // Return combined frame
    if (videoFrame != null) {
      if (audioFrame != null) {
        return MediaFrame.withBoth(videoFrame, audioFrame);
      }
      return MediaFrame.withVideo(videoFrame);
    } else if (audioFrame != null) {
      return MediaFrame.withAudio(audioFrame);
    }

    return null;
  }

  /// Retrieves a specific frame at the given timestamp in milliseconds.
  ///
  /// Returns a [MediaFrame] containing both video and audio data if available,
  /// or null if retrieval failed.
  Future<MediaFrame?> getFrameAtTimestamp(int timestampMs) async {
    if (!_isOpened || timestampMs < 0) return null;

    // Get video frame
    final videoFramePtrPtr = calloc<Pointer<ffi_bindings.VideoFrame>>();
    VideoFrame? videoFrame;

    try {
      final videoResult = _bindings.getVideoFrameAtTimestamp(timestampMs, videoFramePtrPtr);
      if (videoResult >= 0 && videoFramePtrPtr.value != nullptr) {
        videoFrame = _convertAndFreeVideoFrame(videoFramePtrPtr.value);
      }
    } catch (e) {
      // Video retrieval failed
    } finally {
      calloc.free(videoFramePtrPtr);
    }

    // Get audio frame
    final audioFramePtrPtr = calloc<Pointer<ffi_bindings.AudioFrame>>();
    AudioFrame? audioFrame;

    try {
      final audioResult = _bindings.getAudioFrameAtTimestamp(timestampMs, audioFramePtrPtr);
      if (audioResult >= 0 && audioFramePtrPtr.value != nullptr) {
        audioFrame = _convertAndFreeAudioFrame(audioFramePtrPtr.value);
      }
    } catch (e) {
      // Audio retrieval failed
    } finally {
      calloc.free(audioFramePtrPtr);
    }

    // Update frame index if we have a frame
    if (videoFrame != null && _fps > 0) {
      _currentFrameIndex = (videoFrame.pts.inMilliseconds * _fps / 1000).round();
    }

    // Return combined frame
    if (videoFrame != null) {
      if (audioFrame != null) {
        return MediaFrame.withBoth(videoFrame, audioFrame);
      }
      return MediaFrame.withVideo(videoFrame);
    } else if (audioFrame != null) {
      return MediaFrame.withAudio(audioFrame);
    }

    return null;
  }

  /// Retrieves a range of frames by index.
  ///
  /// Returns a list of [MediaFrame] objects. The list may contain fewer frames
  /// than requested if reaching end of media or if retrieval fails.
  Future<List<MediaFrame>> getFramesRangeByIndex(int start, int end) async {
    final frames = <MediaFrame>[];

    for (int i = start; i <= end; i++) {
      final frame = await getFrameAtIndex(i);
      if (frame != null) {
        frames.add(frame);
      } else {
        break; // Stop if frame retrieval fails (likely EOF)
      }
    }

    return frames;
  }

  /// Retrieves a range of frames by timestamp.
  ///
  /// Returns a list of [MediaFrame] objects. The list may contain fewer frames
  /// than requested if reaching end of media or if retrieval fails.
  Future<List<MediaFrame>> getFramesRangeByTimestamp(
      int startMs, int endMs, int stepMs) async {
    final frames = <MediaFrame>[];

    for (int ts = startMs; ts <= endMs; ts += stepMs) {
      final frame = await getFrameAtTimestamp(ts);
      if (frame != null) {
        frames.add(frame);
      } else {
        break; // Stop if frame retrieval fails (likely EOF)
      }
    }

    return frames;
  }

  /// Moves to the next frame.
  ///
  /// Returns the next [MediaFrame] or null if already at the end.
  Future<MediaFrame?> nextFrame() async {
    if (!_isOpened) return null;

    _currentFrameIndex++;
    return await getFrameAtIndex(_currentFrameIndex);
  }

  /// Moves to the previous frame.
  ///
  /// Returns the previous [MediaFrame] or null if already at the beginning.
  Future<MediaFrame?> previousFrame() async {
    if (!_isOpened || _currentFrameIndex <= 0) return null;

    _currentFrameIndex--;
    return await getFrameAtIndex(_currentFrameIndex);
  }

  /// Converts a native video frame to a Dart VideoFrame and frees the native memory.
  VideoFrame _convertAndFreeVideoFrame(Pointer<ffi_bindings.VideoFrame> framePtr) {
    final frame = framePtr.ref;

    // Safety checks
    final dataSize = frame.linesize * frame.height;
    if (dataSize <= 0 || dataSize > 100 * 1024 * 1024) { // Max 100MB
      throw StateError('Invalid video frame data size: $dataSize bytes');
    }

    final rgbaBytes = Uint8List(dataSize);
    
    // Check pointer validity before access
    if (frame.data == nullptr) {
      throw StateError('Native frame data pointer is null');
    }

    // Convert to Pointer<Uint8> and copy data element by element
    final nativePtr = frame.data.cast<Uint8>();
    
    try {
      // Use a safer copy approach - read in chunks to avoid any FFI issues
      const chunkSize = 4096;
      int offset = 0;
      
      while (offset < dataSize) {
        final remaining = dataSize - offset;
        final currentChunk = remaining < chunkSize ? remaining : chunkSize;
        
        for (int i = 0; i < currentChunk; i++) {
          rgbaBytes[offset + i] = nativePtr[offset + i];
        }
        
        offset += currentChunk;
      }
    } catch (e) {
      throw StateError('Failed to copy video frame data: $e');
    }

    final videoFrame = VideoFrame(
      width: frame.width,
      height: frame.height,
      rgbaBytes: rgbaBytes,
      pts: Duration(milliseconds: frame.ptsMs),
      frameId: frame.frameId,
    );

    // Free the native frame AFTER copying data
    _bindings.freeVideoFrame(framePtr);

    return videoFrame;
  }

  /// Converts a native audio frame to a Dart AudioFrame and frees the native memory.
  AudioFrame _convertAndFreeAudioFrame(Pointer<ffi_bindings.AudioFrame> framePtr) {
    final frame = framePtr.ref;

    // Safety checks
    final dataSize = frame.samplesCount * frame.channels;
    if (dataSize <= 0 || dataSize > 10 * 1024 * 1024) { // Max 10M samples
      throw StateError('Invalid audio frame data size: $dataSize samples');
    }

    final samples = Float32List(dataSize);

    // Check pointer validity before access
    if (frame.data == nullptr) {
      throw StateError('Native audio data pointer is null');
    }

    // Convert to Pointer<Float> and copy data sample by sample
    final nativePtr = frame.data.cast<Float>();
    
    try {
      // Copy in chunks for safety
      const chunkSize = 1024;
      int offset = 0;
      
      while (offset < dataSize) {
        final remaining = dataSize - offset;
        final currentChunk = remaining < chunkSize ? remaining : chunkSize;
        
        for (int i = 0; i < currentChunk; i++) {
          samples[offset + i] = nativePtr[offset + i];
        }
        
        offset += currentChunk;
      }
    } catch (e) {
      throw StateError('Failed to copy audio frame data: $e');
    }

    final audioFrame = AudioFrame(
      sampleRate: frame.sampleRate,
      channels: frame.channels,
      samples: samples,
      pts: Duration(milliseconds: frame.ptsMs),
    );

    // Free the native frame AFTER copying data
    _bindings.freeAudioFrame(framePtr);

    return audioFrame;
  }

  /// Releases all resources and closes the media file.
  Future<void> release() async {
    if (_isOpened) {
      _bindings.stop();
      _isOpened = false;
    }

    _durationMs = 0;
    _videoWidth = 0;
    _videoHeight = 0;
    _fps = 0;
    _totalFrames = 0;
    _currentFrameIndex = 0;
  }

  /// Cleans up the native FFmpeg resources.
  Future<void> dispose() async {
    await release();
  }
}