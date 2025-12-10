import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import '../ffi/lotterwise_ffmpeg_bindings.dart' as ffi_bindings;
import '../models/media_info.dart';
import '../models/frame_data.dart';

class FfmpegMediaSource {
  final String path;
  final bool isUrl;

  FfmpegMediaSource.fromFile(this.path) : isUrl = false;
  FfmpegMediaSource.fromUrl(this.path) : isUrl = true;
}

class FfmpegDecoder {
  static final ffi_bindings.LotterwiseFfmpegBindings _bindings = 
      ffi_bindings.LotterwiseFfmpegBindings();
  
  static bool _initialized = false;

  static void ensureInitialized() {
    if (!_initialized) {
      _bindings.init();
      _initialized = true;
    }
  }

  // Streams
  final _videoController = StreamController<VideoFrame>.broadcast();
  final _audioController = StreamController<AudioFrame>.broadcast();

  Stream<VideoFrame> get videoFrames => _videoController.stream;
  Stream<AudioFrame> get audioFrames => _audioController.stream;

  // Native Listeners
  NativeCallable<ffi_bindings.NativeOnVideoFrame>? _videoListener;
  NativeCallable<ffi_bindings.NativeOnAudioFrame>? _audioListener;
  NativeCallable<ffi_bindings.NativeOnLog>? _logListener;

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

  Future<MediaInfo> get mediaInfo async {
    final info = _bindings.getMediaInfo();
    return MediaInfo(
      duration: Duration(milliseconds: info.durationMs),
      width: info.width,
      height: info.height,
      fps: info.fps,
      audioSampleRate: info.audioSampleRate,
      audioChannels: info.audioChannels,
    );
  }

  Future<void> play() async {
    _bindings.startDecoding();
    _bindings.resume();
  }

  Future<void> pause() async {
    _bindings.pause();
  }

  Future<void> seek(Duration position) async {
    _bindings.seek(position.inMilliseconds);
  }

  Future<void> close() async {
    _bindings.stop();
    _videoListener?.close();
    _audioListener?.close();
    _logListener?.close();
    _videoController.close();
    _audioController.close();
  }

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
