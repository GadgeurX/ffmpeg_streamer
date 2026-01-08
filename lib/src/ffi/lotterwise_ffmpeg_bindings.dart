import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

// --- Type Definitions ---

typedef RequestId = int;

// Callback types for async operations
typedef NativeOnVideoFrameCallback = Void Function(
    Pointer<Void> userData, Pointer<VideoFrame> frame, Int32 errorCode);
typedef DartOnVideoFrameCallback = void Function(
    Pointer<Void> userData, Pointer<VideoFrame> frame, int errorCode);

typedef NativeOnAudioFrameCallback = Void Function(
    Pointer<Void> userData, Pointer<AudioFrame> frame, Int32 errorCode);
typedef DartOnAudioFrameCallback = void Function(
    Pointer<Void> userData, Pointer<AudioFrame> frame, int errorCode);

typedef NativeOnFrameRangeProgressCallback = Void Function(
    Pointer<Void> userData, Int32 current, Int32 total);
typedef DartOnFrameRangeProgressCallback = void Function(
    Pointer<Void> userData, int current, int total);

// --- Structs ---

final class MediaInfo extends Struct {
  @Int64()
  external int durationMs;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Double()
  external double fps;

  @Int32()
  external int audioSampleRate;

  @Int32()
  external int audioChannels;

  @Int64()
  external int totalFrames;
}

final class VideoFrame extends Struct {
  external Pointer<Uint8> data;

  @Int32()
  external int width;

  @Int32()
  external int height;

  @Int32()
  external int linesize;

  @Int64()
  external int ptsMs;

  @Int64()
  external int frameId;
}

final class AudioFrame extends Struct {
  external Pointer<Float> data;

  @Int32()
  external int samplesCount;

  @Int32()
  external int channels;

  @Int32()
  external int sampleRate;

  @Int64()
  external int ptsMs;

  @Int64()
  external int frameId;
}

// --- Function Signatures ---

typedef NativeFfmpegInit = Void Function();
typedef DartFfmpegInit = void Function();

typedef NativeFfmpegRelease = Void Function();
typedef DartFfmpegRelease = void Function();

typedef NativeFfmpegOpenMedia = Int32 Function(Pointer<Utf8> url);
typedef DartFfmpegOpenMedia = int Function(Pointer<Utf8> url);

typedef NativeFfmpegGetMediaInfo = MediaInfo Function();
typedef DartFfmpegGetMediaInfo = MediaInfo Function();

typedef NativeFfmpegStop = Void Function();
typedef DartFfmpegStop = void Function();

typedef NativeFfmpegFreeVideoFrame = Void Function(Pointer<VideoFrame> frame);
typedef DartFfmpegFreeVideoFrame = void Function(Pointer<VideoFrame> frame);

typedef NativeFfmpegFreeAudioFrame = Void Function(Pointer<AudioFrame> frame);
typedef DartFfmpegFreeAudioFrame = void Function(Pointer<AudioFrame> frame);

// --- Async Frame Retrieval Functions ---

typedef NativeFfmpegGetVideoFrameAtTimestampAsync = Int64 Function(
    Int64 timestampMs,
    Pointer<NativeFunction<NativeOnVideoFrameCallback>> callback,
    Pointer<Void> userData);
typedef DartFfmpegGetVideoFrameAtTimestampAsync = int Function(
    int timestampMs,
    Pointer<NativeFunction<NativeOnVideoFrameCallback>> callback,
    Pointer<Void> userData);

typedef NativeFfmpegGetVideoFrameAtIndexAsync = Int64 Function(
    Int32 frameIndex,
    Pointer<NativeFunction<NativeOnVideoFrameCallback>> callback,
    Pointer<Void> userData);
typedef DartFfmpegGetVideoFrameAtIndexAsync = int Function(
    int frameIndex,
    Pointer<NativeFunction<NativeOnVideoFrameCallback>> callback,
    Pointer<Void> userData);

typedef NativeFfmpegGetAudioFrameAtTimestampAsync = Int64 Function(
    Int64 timestampMs,
    Pointer<NativeFunction<NativeOnAudioFrameCallback>> callback,
    Pointer<Void> userData);
typedef DartFfmpegGetAudioFrameAtTimestampAsync = int Function(
    int timestampMs,
    Pointer<NativeFunction<NativeOnAudioFrameCallback>> callback,
    Pointer<Void> userData);

typedef NativeFfmpegGetAudioFrameAtIndexAsync = Int64 Function(
    Int32 frameIndex,
    Pointer<NativeFunction<NativeOnAudioFrameCallback>> callback,
    Pointer<Void> userData);
typedef DartFfmpegGetAudioFrameAtIndexAsync = int Function(
    int frameIndex,
    Pointer<NativeFunction<NativeOnAudioFrameCallback>> callback,
    Pointer<Void> userData);

typedef NativeFfmpegGetVideoFramesRangeAsync = Int64 Function(
    Int32 startIndex,
    Int32 endIndex,
    Pointer<NativeFunction<NativeOnVideoFrameCallback>> frameCallback,
    Pointer<NativeFunction<NativeOnFrameRangeProgressCallback>>
        progressCallback,
    Pointer<Void> userData);
typedef DartFfmpegGetVideoFramesRangeAsync = int Function(
    int startIndex,
    int endIndex,
    Pointer<NativeFunction<NativeOnVideoFrameCallback>> frameCallback,
    Pointer<NativeFunction<NativeOnFrameRangeProgressCallback>>
        progressCallback,
    Pointer<Void> userData);

typedef NativeFfmpegCancelRequest = Void Function(Int64 requestId);
typedef DartFfmpegCancelRequest = void Function(int requestId);

// --- Bindings Class ---

class LotterwiseFfmpegBindings {
  late final DynamicLibrary _dylib;

  late final DartFfmpegInit init;
  late final DartFfmpegRelease release;
  late final DartFfmpegOpenMedia openMedia;
  late final DartFfmpegGetMediaInfo getMediaInfo;
  late final DartFfmpegStop stop;
  late final DartFfmpegFreeVideoFrame freeVideoFrame;
  late final DartFfmpegFreeAudioFrame freeAudioFrame;

  // Async functions
  late final DartFfmpegGetVideoFrameAtTimestampAsync
      getVideoFrameAtTimestampAsync;
  late final DartFfmpegGetVideoFrameAtIndexAsync getVideoFrameAtIndexAsync;
  late final DartFfmpegGetAudioFrameAtTimestampAsync
      getAudioFrameAtTimestampAsync;
  late final DartFfmpegGetAudioFrameAtIndexAsync getAudioFrameAtIndexAsync;
  late final DartFfmpegGetVideoFramesRangeAsync getVideoFramesRangeAsync;
  late final DartFfmpegCancelRequest cancelRequest;

  LotterwiseFfmpegBindings() {
    _dylib = _loadDynamicLibrary();

    init = _dylib.lookupFunction<NativeFfmpegInit, DartFfmpegInit>(
        'ffmpeg_init');
    release = _dylib.lookupFunction<NativeFfmpegRelease, DartFfmpegRelease>(
        'ffmpeg_release');
    openMedia = _dylib.lookupFunction<NativeFfmpegOpenMedia,
        DartFfmpegOpenMedia>('ffmpeg_open_media');
    getMediaInfo = _dylib.lookupFunction<NativeFfmpegGetMediaInfo,
        DartFfmpegGetMediaInfo>('ffmpeg_get_media_info');
    stop = _dylib.lookupFunction<NativeFfmpegStop, DartFfmpegStop>('ffmpeg_stop');
    freeVideoFrame = _dylib.lookupFunction<NativeFfmpegFreeVideoFrame,
        DartFfmpegFreeVideoFrame>('ffmpeg_free_video_frame');
    freeAudioFrame = _dylib.lookupFunction<NativeFfmpegFreeAudioFrame,
        DartFfmpegFreeAudioFrame>('ffmpeg_free_audio_frame');

    // Async functions
    getVideoFrameAtTimestampAsync = _dylib.lookupFunction<
        NativeFfmpegGetVideoFrameAtTimestampAsync,
        DartFfmpegGetVideoFrameAtTimestampAsync>(
        'ffmpeg_get_video_frame_at_timestamp_async');
    getVideoFrameAtIndexAsync = _dylib.lookupFunction<
        NativeFfmpegGetVideoFrameAtIndexAsync,
        DartFfmpegGetVideoFrameAtIndexAsync>(
        'ffmpeg_get_video_frame_at_index_async');
    getAudioFrameAtTimestampAsync = _dylib.lookupFunction<
        NativeFfmpegGetAudioFrameAtTimestampAsync,
        DartFfmpegGetAudioFrameAtTimestampAsync>(
        'ffmpeg_get_audio_frame_at_timestamp_async');
    getAudioFrameAtIndexAsync = _dylib.lookupFunction<
        NativeFfmpegGetAudioFrameAtIndexAsync,
        DartFfmpegGetAudioFrameAtIndexAsync>(
        'ffmpeg_get_audio_frame_at_index_async');
    getVideoFramesRangeAsync = _dylib.lookupFunction<
        NativeFfmpegGetVideoFramesRangeAsync,
        DartFfmpegGetVideoFramesRangeAsync>(
        'ffmpeg_get_video_frames_range_async');
    cancelRequest = _dylib.lookupFunction<NativeFfmpegCancelRequest,
        DartFfmpegCancelRequest>('ffmpeg_cancel_request');
  }

  static DynamicLibrary _loadDynamicLibrary() {
    if (Platform.isIOS || Platform.isMacOS) {
      return DynamicLibrary.process(); // Linked into the app process
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libffmpeg_streamer.so');
    } else if (Platform.isWindows) {
      return DynamicLibrary.open('ffmpeg_streamer.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libffmpeg_streamer.so');
    }
    throw UnsupportedError('Unknown platform: ${Platform.operatingSystem}');
  }
}