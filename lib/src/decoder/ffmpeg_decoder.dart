import 'dart:ffi';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/lotterwise_ffmpeg_bindings.dart' as ffi_bindings;
import '../models/frame_data.dart';

/// Callback type for when a frame is retrieved asynchronously.
typedef OnFrameCallback = void Function(MediaFrame? frame);

/// Callback type for frame range progress updates.
typedef OnProgressCallback = void Function(int current, int total);

/// FFmpeg-based decoder for media files with async API.
/// All frame retrieval is asynchronous using native threads for optimal performance.
class FfmpegDecoder {
  final ffi_bindings.LotterwiseFfmpegBindings _bindings;

  bool _isInitialized = false;
  bool _isOpened = false;

  int _durationMs = 0;
  int _videoWidth = 0;
  int _videoHeight = 0;
  double _fps = 0;
  int _totalFrames = 0;

  int _audioSampleRate = 0;
  int _audioChannels = 0;

  // Callback management
  final Map<int, _PendingRequest> _pendingRequests = {};
  int _nextCallbackId = 1;

  // Native callbacks (use static methods with NativeCallable for thread safety)
  static late final NativeCallable<ffi_bindings.NativeOnVideoFrameCallback>
      _videoFrameCallable;
  static late final NativeCallable<ffi_bindings.NativeOnAudioFrameCallback>
      _audioFrameCallable;
  static late final NativeCallable<ffi_bindings.NativeOnFrameRangeProgressCallback>
      _progressCallable;

  static late final Pointer<NativeFunction<ffi_bindings.NativeOnVideoFrameCallback>>
      _videoFrameCallbackPointer;
  static late final Pointer<NativeFunction<ffi_bindings.NativeOnAudioFrameCallback>>
      _audioFrameCallbackPointer;
  static late final Pointer<
          NativeFunction<ffi_bindings.NativeOnFrameRangeProgressCallback>>
      _progressCallbackPointer;
  
  static bool _callbacksInitialized = false;

  /// Creates a new FFmpeg decoder instance.
  FfmpegDecoder() : _bindings = ffi_bindings.LotterwiseFfmpegBindings() {
    _initialize();
    _register();
  }

  /// Initializes FFmpeg library.
  void _initialize() {
    if (_isInitialized) return;

    _bindings.init();

    // Initialize native callbacks (only once for all instances)
    if (!_callbacksInitialized) {
      _videoFrameCallable = NativeCallable<ffi_bindings.NativeOnVideoFrameCallback>.listener(
        _onVideoFrameCallback,
      );
      _audioFrameCallable = NativeCallable<ffi_bindings.NativeOnAudioFrameCallback>.listener(
        _onAudioFrameCallback,
      );
      _progressCallable = NativeCallable<ffi_bindings.NativeOnFrameRangeProgressCallback>.listener(
        _onProgressCallback,
      );

      _videoFrameCallbackPointer = _videoFrameCallable.nativeFunction;
      _audioFrameCallbackPointer = _audioFrameCallable.nativeFunction;
      _progressCallbackPointer = _progressCallable.nativeFunction;

      _callbacksInitialized = true;
    }

    _isInitialized = true;
  }
  
  /// Register this decoder instance.
  void _register() {
    _FfmpegDecoderRegistry._register(this);
  }

  /// Opens a media file.
  ///
  /// Returns [true] if the file was opened successfully.
  Future<bool> openMedia(String filePath) async {
    if (!_isInitialized) {
      _initialize();
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

  /// Retrieves a specific frame by its index (ASYNC with callback).
  ///
  /// This method uses native threading for optimal performance.
  /// The callback will be invoked when the frame is ready.
  ///
  /// Returns a request ID that can be used to cancel the request.
  int getFrameAtIndexAsync(int index, OnFrameCallback callback) {
    if (!_isOpened || index < 0) {
      callback(null);
      return -1;
    }

    final callbackId = _nextCallbackId++;
    final request = _PendingRequest(
      callbackId: callbackId,
      videoCallback: callback,
      hasVideo: true,
      hasAudio: true,
    );
    _pendingRequests[callbackId] = request;

    // Create user data pointer with callback ID
    final userData = calloc<Int64>();
    userData.value = callbackId;

    // Request video frame
    final videoRequestId = _bindings.getVideoFrameAtIndexAsync(
      index,
      _videoFrameCallbackPointer,
      userData.cast(),
    );

    if (videoRequestId < 0) {
      calloc.free(userData);
      _pendingRequests.remove(callbackId);
      callback(null);
      return -1;
    }

    request.videoRequestId = videoRequestId;

    // Request audio frame
    final audioRequestId = _bindings.getAudioFrameAtIndexAsync(
      index,
      _audioFrameCallbackPointer,
      userData.cast(),
    );

    if (audioRequestId >= 0) {
      request.audioRequestId = audioRequestId;
    }

    return callbackId;
  }

  /// Retrieves a specific frame at the given timestamp in milliseconds (ASYNC).
  ///
  /// The callback will be invoked when the frame is ready.
  ///
  /// Returns a request ID that can be used to cancel the request.
  int getFrameAtTimestampAsync(int timestampMs, OnFrameCallback callback) {
    if (!_isOpened || timestampMs < 0) {
      callback(null);
      return -1;
    }

    final callbackId = _nextCallbackId++;
    final request = _PendingRequest(
      callbackId: callbackId,
      videoCallback: callback,
      hasVideo: true,
      hasAudio: true,
    );
    _pendingRequests[callbackId] = request;

    final userData = calloc<Int64>();
    userData.value = callbackId;

    final videoRequestId = _bindings.getVideoFrameAtTimestampAsync(
      timestampMs,
      _videoFrameCallbackPointer,
      userData.cast(),
    );

    if (videoRequestId < 0) {
      calloc.free(userData);
      _pendingRequests.remove(callbackId);
      callback(null);
      return -1;
    }

    request.videoRequestId = videoRequestId;

    final audioRequestId = _bindings.getAudioFrameAtTimestampAsync(
      timestampMs,
      _audioFrameCallbackPointer,
      userData.cast(),
    );

    if (audioRequestId >= 0) {
      request.audioRequestId = audioRequestId;
    }

    return callbackId;
  }

  /// Retrieves a range of frames by index (OPTIMIZED ASYNC).
  ///
  /// This method uses an optimized C implementation that seeks once
  /// and decodes sequentially, much faster than multiple individual requests.
  ///
  /// [frameCallback] is called for each frame as it becomes available.
  /// [progressCallback] is called to report progress (optional).
  ///
  /// Returns a request ID that can be used to cancel the request.
  int getFramesRangeByIndexAsync(
    int start,
    int end,
    OnFrameCallback frameCallback, {
    OnProgressCallback? progressCallback,
  }) {
    if (!_isOpened || start < 0 || end < start) {
      return -1;
    }

    final callbackId = _nextCallbackId++;
    final request = _PendingRequest(
      callbackId: callbackId,
      videoCallback: frameCallback,
      progressCallback: progressCallback,
      hasVideo: true,
      hasAudio: false,
      isRange: true,
    );
    _pendingRequests[callbackId] = request;

    final userData = calloc<Int64>();
    userData.value = callbackId;

    final requestId = _bindings.getVideoFramesRangeAsync(
      start,
      end,
      _videoFrameCallbackPointer,
      progressCallback != null ? _progressCallbackPointer : nullptr,
      userData.cast(),
    );

    if (requestId < 0) {
      calloc.free(userData);
      _pendingRequests.remove(callbackId);
      return -1;
    }

    request.videoRequestId = requestId;

    return callbackId;
  }

  /// Cancels an async request.
  void cancelRequest(int requestId) {
    final request = _pendingRequests[requestId];
    if (request != null) {
      if (request.videoRequestId > 0) {
        _bindings.cancelRequest(request.videoRequestId);
      }
      if (request.audioRequestId > 0) {
        _bindings.cancelRequest(request.audioRequestId);
      }
      _pendingRequests.remove(requestId);
    }
  }

  // --- Native Callback Handlers ---

  static void _onVideoFrameCallback(
      Pointer<Void> userData, Pointer<ffi_bindings.VideoFrame> frame, int errorCode) {
    if (userData == nullptr) return;

    final callbackId = userData.cast<Int64>().value;
    _FfmpegDecoderRegistry._handleVideoFrame(callbackId, frame, errorCode);
  }

  static void _onAudioFrameCallback(
      Pointer<Void> userData, Pointer<ffi_bindings.AudioFrame> frame, int errorCode) {
    if (userData == nullptr) return;

    final callbackId = userData.cast<Int64>().value;
    _FfmpegDecoderRegistry._handleAudioFrame(callbackId, frame, errorCode);
  }

  static void _onProgressCallback(Pointer<Void> userData, int current, int total) {
    if (userData == nullptr) return;

    final callbackId = userData.cast<Int64>().value;
    _FfmpegDecoderRegistry._handleProgress(callbackId, current, total);
  }

  void _handleVideoFrameInternal(int callbackId, Pointer<ffi_bindings.VideoFrame> framePtr, int errorCode) {
    final request = _pendingRequests[callbackId];
    if (request == null) return;

    if (errorCode >= 0 && framePtr != nullptr) {
      try {
        request.videoFrame = _convertAndFreeVideoFrame(framePtr);
      } catch (e) {
        request.videoFrame = null;
      }
    }

    request.videoCompleted = true;
    _checkAndInvokeCallback(callbackId);
  }

  void _handleAudioFrameInternal(int callbackId, Pointer<ffi_bindings.AudioFrame> framePtr, int errorCode) {
    final request = _pendingRequests[callbackId];
    if (request == null) return;

    if (errorCode >= 0 && framePtr != nullptr) {
      try {
        request.audioFrame = _convertAndFreeAudioFrame(framePtr);
      } catch (e) {
        request.audioFrame = null;
      }
    }

    request.audioCompleted = true;
    _checkAndInvokeCallback(callbackId);
  }

  void _handleProgressInternal(int callbackId, int current, int total) {
    final request = _pendingRequests[callbackId];
    if (request == null) return;

    if (request.progressCallback != null) {
      request.progressCallback!(current, total);
    }
  }

  void _checkAndInvokeCallback(int callbackId) {
    final request = _pendingRequests[callbackId];
    if (request == null) return;

    // For range requests, invoke callback immediately for each frame
    if (request.isRange) {
      if (request.videoCompleted && request.videoFrame != null) {
        final mediaFrame = MediaFrame.withVideo(request.videoFrame!);
        request.videoCallback?.call(mediaFrame);
        request.videoCompleted = false;
        request.videoFrame = null;
      }
      return;
    }

    // For single requests, wait for both video and audio
    if (!request.videoCompleted || (request.hasAudio && !request.audioCompleted)) {
      return;
    }

    // Combine frames and invoke callback
    MediaFrame? mediaFrame;
    if (request.videoFrame != null) {
      if (request.audioFrame != null) {
        mediaFrame = MediaFrame.withBoth(request.videoFrame!, request.audioFrame!);
      } else {
        mediaFrame = MediaFrame.withVideo(request.videoFrame!);
      }
    } else if (request.audioFrame != null) {
      mediaFrame = MediaFrame.withAudio(request.audioFrame!);
    }

    request.videoCallback?.call(mediaFrame);
    _pendingRequests.remove(callbackId);
  }

  /// Converts a native video frame to a Dart VideoFrame and frees the native memory.
  VideoFrame _convertAndFreeVideoFrame(Pointer<ffi_bindings.VideoFrame> framePtr) {
    final frame = framePtr.ref;

    final dataSize = frame.linesize * frame.height;
    if (dataSize <= 0 || dataSize > 100 * 1024 * 1024) {
      throw StateError('Invalid video frame data size: $dataSize bytes');
    }

    final rgbaBytes = Uint8List(dataSize);

    if (frame.data == nullptr) {
      throw StateError('Native frame data pointer is null');
    }

    final nativePtr = frame.data.cast<Uint8>();

    try {
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

    _bindings.freeVideoFrame(framePtr);

    return videoFrame;
  }

  /// Converts a native audio frame to a Dart AudioFrame and frees the native memory.
  AudioFrame _convertAndFreeAudioFrame(Pointer<ffi_bindings.AudioFrame> framePtr) {
    final frame = framePtr.ref;

    final dataSize = frame.samplesCount * frame.channels;
    if (dataSize <= 0 || dataSize > 10 * 1024 * 1024) {
      throw StateError('Invalid audio frame data size: $dataSize samples');
    }

    final samples = Float32List(dataSize);

    if (frame.data == nullptr) {
      throw StateError('Native audio data pointer is null');
    }

    final nativePtr = frame.data.cast<Float>();

    try {
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

    _bindings.freeAudioFrame(framePtr);

    return audioFrame;
  }

  /// Releases all resources and closes the media file.
  Future<void> release() async {
    // Cancel all pending requests
    for (final callbackId in _pendingRequests.keys.toList()) {
      cancelRequest(callbackId);
    }

    if (_isOpened) {
      _bindings.stop();
      _isOpened = false;
    }

    _durationMs = 0;
    _videoWidth = 0;
    _videoHeight = 0;
    _fps = 0;
    _totalFrames = 0;
  }

  /// Cleans up the native FFmpeg resources.
  Future<void> dispose() async {
    await release();
    _FfmpegDecoderRegistry._unregister(this);
  }
}

/// Internal class to track pending async requests.
class _PendingRequest {
  final int callbackId;
  int videoRequestId = 0;
  int audioRequestId = 0;
  
  OnFrameCallback? videoCallback;
  OnProgressCallback? progressCallback;
  
  bool hasVideo;
  bool hasAudio;
  bool isRange;
  
  bool videoCompleted = false;
  bool audioCompleted = false;
  
  VideoFrame? videoFrame;
  AudioFrame? audioFrame;

  _PendingRequest({
    required this.callbackId,
    this.videoCallback,
    this.progressCallback,
    this.hasVideo = false,
    this.hasAudio = false,
    this.isRange = false,
  });
}

/// Global registry to manage decoder instances and route callbacks.
class _FfmpegDecoderRegistry {
  static final Map<int, FfmpegDecoder> _decoders = {};
  static int _nextId = 1;

  static void _register(FfmpegDecoder decoder) {
    final id = _nextId++;
    _decoders[id] = decoder;
  }

  static void _unregister(FfmpegDecoder decoder) {
    _decoders.removeWhere((key, value) => value == decoder);
  }

  static void _handleVideoFrame(int callbackId, Pointer<ffi_bindings.VideoFrame> frame, int errorCode) {
    // Find the decoder that has this callback ID
    for (final decoder in _decoders.values) {
      if (decoder._pendingRequests.containsKey(callbackId)) {
        decoder._handleVideoFrameInternal(callbackId, frame, errorCode);
        break;
      }
    }
  }

  static void _handleAudioFrame(int callbackId, Pointer<ffi_bindings.AudioFrame> frame, int errorCode) {
    for (final decoder in _decoders.values) {
      if (decoder._pendingRequests.containsKey(callbackId)) {
        decoder._handleAudioFrameInternal(callbackId, frame, errorCode);
        break;
      }
    }
  }

  static void _handleProgress(int callbackId, int current, int total) {
    for (final decoder in _decoders.values) {
      if (decoder._pendingRequests.containsKey(callbackId)) {
        decoder._handleProgressInternal(callbackId, current, total);
        break;
      }
    }
  }
}
