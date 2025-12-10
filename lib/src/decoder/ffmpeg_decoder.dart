import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/lotterwise_ffmpeg_bindings.dart' as ffi_bindings;
import '../models/media_info.dart';
import '../models/frame_data.dart';

/// Represents a source for FFmpeg media, either a file path or a URL.
class FfmpegMediaSource {
  /// The path to the media file or the URL string.
  final String path;
  
  /// Whether the source is a URL (true) or a local file path (false).
  final bool isUrl;

  /// Creates a media source from a local file path.
  FfmpegMediaSource.fromFile(this.path) : isUrl = false;

  /// Creates a media source from a network URL.
  FfmpegMediaSource.fromUrl(this.path) : isUrl = true;
}

/// A decoder using FFmpeg native bindings to read video and audio frames.
class FfmpegDecoder {
  static final ffi_bindings.LotterwiseFfmpegBindings _bindings = 
      ffi_bindings.LotterwiseFfmpegBindings();
  
  static bool _initialized = false;

  /// Ensures that the native FFmpeg bindings are initialized.
  /// This is called automatically by [open].
  static void ensureInitialized() {
    if (!_initialized) {
      _bindings.init();
      _initialized = true;
    }
  }

  // Streams
  final _videoController = StreamController<VideoFrame>.broadcast();
  final _audioController = StreamController<AudioFrame>.broadcast();

  /// Stream of decoded video frames.
  /// Listen to this stream to render video playback.
  Stream<VideoFrame> get videoFrames => _videoController.stream;

  /// Stream of decoded audio frames.
  /// Listen to this stream to play audio.
  Stream<AudioFrame> get audioFrames => _audioController.stream;

  // Native Listeners
  NativeCallable<ffi_bindings.NativeOnVideoFrame>? _videoListener;
  NativeCallable<ffi_bindings.NativeOnAudioFrame>? _audioListener;
  NativeCallable<ffi_bindings.NativeOnLog>? _logListener;

  /// Opens a media source for decoding.
  ///
  /// This initializes the decoder, sets up native callbacks, and opens the
  /// specified [source].
  ///
  /// Throws an exception if opening the media fails.
  Future<void> open(FfmpegMediaSource source) async {
    ensureInitialized();

    // Setup Callbacks
    _videoListener = NativeCallable<ffi_bindings.NativeOnVideoFrame>.listener(_onVideoFrame);
    _audioListener = NativeCallable<ffi_bindings.NativeOnAudioFrame>.listener(_onAudioFrame);
    _logListener = NativeCallable<ffi_bindings.NativeOnLog>.listener(_onLog);

    _bindings.setCallbacks(
      _videoListener!.nativeFunction,
      _audioListener!.nativeFunction,
      _logListener!.nativeFunction,
    );
    
    final pathPtr = source.path.toNativeUtf8();
    final result = _bindings.openMedia(pathPtr);
    calloc.free(pathPtr);

    if (result < 0) {
      throw Exception('Failed to open media: error code $result');
    }
  }

  /// Retrieves media information such as duration, resolution, and frame rate.
  /// 
  /// This should be called after [open].
  Future<MediaInfo> get mediaInfo async {
    final info = _bindings.getMediaInfo();
    return MediaInfo(
      duration: Duration(milliseconds: info.durationMs),
      width: info.width,
      height: info.height,
      fps: info.fps,
      audioSampleRate: info.audioSampleRate,
      audioChannels: info.audioChannels,
      totalFrames: info.totalFrames,
    );
  }

  /// Starts or resumes decoding.
  ///
  /// This triggers the native decoder loop which will start emitting frames
  /// to [videoFrames] and [audioFrames].
  Future<void> play() async {
    _bindings.startDecoding();
    _bindings.resume();
  }



  /// Pauses decoding.
  Future<void> pause() async {
    _bindings.pause();
  }



  Future<void> seek(Duration position) async {
    _bindings.seek(position.inMilliseconds);
  }

  /// Seeks to a specific frame index.
  Future<void> seekToFrame(int frameIndex) async {
    _bindings.seekFrame(frameIndex);
  }

  /// Retrieves a specific video frame at the given timestamp in milliseconds.
  ///
  /// Returns `null` if the frame could not be retrieved.
  Future<VideoFrame?> getFrameAtTimestamp(int timestampMs) async {
    final framePtrPtr = calloc<Pointer<ffi_bindings.VideoFrame>>();
    
    try {
      final result = _bindings.getFrameAtTimestamp(timestampMs, framePtrPtr);
      if (result < 0 || framePtrPtr.value == nullptr) {
        return null;
      }
      
      return _convertAndFreeFrame(framePtrPtr.value);
    } finally {
      calloc.free(framePtrPtr);
    }
  }



  /// Retrieves a specific video frame by its index.
  ///
  /// Returns `null` if the frame could not be retrieved.
  Future<VideoFrame?> getFrameAtIndex(int index) async {
    final framePtrPtr = calloc<Pointer<ffi_bindings.VideoFrame>>();
    
    try {
      final result = _bindings.getFrameAtIndex(index, framePtrPtr);
       if (result < 0 || framePtrPtr.value == nullptr) {
        return null;
      }
      return _convertAndFreeFrame(framePtrPtr.value);
    } finally {
      calloc.free(framePtrPtr);
    }
  }

  VideoFrame _convertAndFreeFrame(Pointer<ffi_bindings.VideoFrame> framePtr) {
    try {
      final frame = framePtr.ref;
      final size = frame.linesize * frame.height;
      final data = Uint8List.fromList(frame.data.asTypedList(size));
      
      return VideoFrame(
        rgbaBytes: data,
        width: frame.width,
        height: frame.height,
        pts: Duration(milliseconds: frame.ptsMs),
        frameId: frame.frameId,
      );
    } finally {
      _bindings.freeFrame(framePtr);
    }
  }



  /// Closes the decoder and releases resources.
  ///
  /// Stops the decoding loop and closes stream controllers and native listeners.
  /// Ideally call [dispose] instead which aliases this method.
  Future<void> close() async {
    _bindings.stop();
    _videoListener?.close();
    _audioListener?.close();
    _logListener?.close();
    _videoController.close();
    _audioController.close();
  }



  /// Disposes the decoder, releasing all native and Dart resources.
  void dispose() {
    close();
  }

  // --- Internal Callbacks ---
  
  void _onVideoFrame(Pointer<ffi_bindings.VideoFrame> framePtr) {
    if (_videoController.isClosed) return;
    
    final frame = framePtr.ref;
    final size = frame.linesize * frame.height;
    
    // Copy data to Dart heap
    final data = Uint8List.fromList(frame.data.asTypedList(size));

    _videoController.add(VideoFrame(
      rgbaBytes: data,
      width: frame.width,
      height: frame.height,
      pts: Duration(milliseconds: frame.ptsMs),
      frameId: frame.frameId,
    ));
  }

  void _onAudioFrame(Pointer<ffi_bindings.AudioFrame> framePtr) {
    if (_audioController.isClosed) return;

    final frame = framePtr.ref;
    final totalSamples = frame.samplesCount * frame.channels;
    
    // Copy data
    final data = Float32List.fromList(frame.data.asTypedList(totalSamples));

    _audioController.add(AudioFrame(
      samples: data,
      sampleRate: frame.sampleRate,
      channels: frame.channels,
      pts: Duration(milliseconds: frame.ptsMs),
    ));
  }

  void _onLog(int level, Pointer<Utf8> msg) {
    if (level < 2) { // Errors & warnings
      //print('[FFmpeg Log] ${msg.toDartString()}');
    }
  }
}
