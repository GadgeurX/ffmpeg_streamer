import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

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

typedef NativeFfmpegSeek = Int32 Function(Int64 timestampMs);
typedef DartFfmpegSeek = int Function(int timestampMs);

typedef NativeFfmpegSeekFrame = Int32 Function(Int32 frameIndex);
typedef DartFfmpegSeekFrame = int Function(int frameIndex);

typedef NativeFfmpegStop = Void Function();
typedef DartFfmpegStop = void Function();

// --- Frame Retrieval Functions ---

typedef NativeFfmpegGetVideoFrameAtTimestamp =
    Int32 Function(Int64 timestampMs, Pointer<Pointer<VideoFrame>> outFrame);
typedef DartFfmpegGetVideoFrameAtTimestamp = int Function(
    int timestampMs, Pointer<Pointer<VideoFrame>> outFrame);

typedef NativeFfmpegGetVideoFrameAtIndex =
    Int32 Function(Int32 frameIndex, Pointer<Pointer<VideoFrame>> outFrame);
typedef DartFfmpegGetVideoFrameAtIndex = int Function(
    int frameIndex, Pointer<Pointer<VideoFrame>> outFrame);

typedef NativeFfmpegGetAudioFrameAtTimestamp =
    Int32 Function(Int64 timestampMs, Pointer<Pointer<AudioFrame>> outFrame);
typedef DartFfmpegGetAudioFrameAtTimestamp = int Function(
    int timestampMs, Pointer<Pointer<AudioFrame>> outFrame);

typedef NativeFfmpegGetAudioFrameAtIndex =
    Int32 Function(Int32 frameIndex, Pointer<Pointer<AudioFrame>> outFrame);
typedef DartFfmpegGetAudioFrameAtIndex = int Function(
    int frameIndex, Pointer<Pointer<AudioFrame>> outFrame);

typedef NativeFfmpegFreeVideoFrame = Void Function(Pointer<VideoFrame> frame);
typedef DartFfmpegFreeVideoFrame = void Function(Pointer<VideoFrame> frame);

typedef NativeFfmpegFreeAudioFrame = Void Function(Pointer<AudioFrame> frame);
typedef DartFfmpegFreeAudioFrame = void Function(Pointer<AudioFrame> frame);

// --- Bindings Class ---

class LotterwiseFfmpegBindings {
  late final DynamicLibrary _dylib;

  late final DartFfmpegInit init;
  late final DartFfmpegRelease release;
  late final DartFfmpegOpenMedia openMedia;
  late final DartFfmpegGetMediaInfo getMediaInfo;
  late final DartFfmpegSeek seek;
  late final DartFfmpegSeekFrame seekFrame;
  late final DartFfmpegStop stop;

  late final DartFfmpegGetVideoFrameAtTimestamp getVideoFrameAtTimestamp;
  late final DartFfmpegGetVideoFrameAtIndex getVideoFrameAtIndex;
  late final DartFfmpegGetAudioFrameAtTimestamp getAudioFrameAtTimestamp;
  late final DartFfmpegGetAudioFrameAtIndex getAudioFrameAtIndex;
  late final DartFfmpegFreeVideoFrame freeVideoFrame;
  late final DartFfmpegFreeAudioFrame freeAudioFrame;

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
    seek = _dylib.lookupFunction<NativeFfmpegSeek, DartFfmpegSeek>(
        'ffmpeg_seek');
    seekFrame = _dylib.lookupFunction<NativeFfmpegSeekFrame, DartFfmpegSeekFrame>(
        'ffmpeg_seek_frame');
    stop =
        _dylib.lookupFunction<NativeFfmpegStop, DartFfmpegStop>('ffmpeg_stop');

    getVideoFrameAtTimestamp = _dylib.lookupFunction<
        NativeFfmpegGetVideoFrameAtTimestamp,
        DartFfmpegGetVideoFrameAtTimestamp>(
        'ffmpeg_get_video_frame_at_timestamp');
    getVideoFrameAtIndex = _dylib.lookupFunction<
        NativeFfmpegGetVideoFrameAtIndex, DartFfmpegGetVideoFrameAtIndex>(
        'ffmpeg_get_video_frame_at_index');
    getAudioFrameAtTimestamp = _dylib.lookupFunction<
        NativeFfmpegGetAudioFrameAtTimestamp,
        DartFfmpegGetAudioFrameAtTimestamp>(
        'ffmpeg_get_audio_frame_at_timestamp');
    getAudioFrameAtIndex = _dylib.lookupFunction<
        NativeFfmpegGetAudioFrameAtIndex, DartFfmpegGetAudioFrameAtIndex>(
        'ffmpeg_get_audio_frame_at_index');
    freeVideoFrame = _dylib.lookupFunction<NativeFfmpegFreeVideoFrame,
        DartFfmpegFreeVideoFrame>('ffmpeg_free_video_frame');
    freeAudioFrame = _dylib.lookupFunction<NativeFfmpegFreeAudioFrame,
        DartFfmpegFreeAudioFrame>('ffmpeg_free_audio_frame');
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