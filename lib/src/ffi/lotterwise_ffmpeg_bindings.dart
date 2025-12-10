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
}

// --- Callback Signatures ---

typedef NativeOnVideoFrame = Void Function(Pointer<VideoFrame> frame);
typedef DartOnVideoFrame = void Function(Pointer<VideoFrame> frame);

typedef NativeOnAudioFrame = Void Function(Pointer<AudioFrame> frame);
typedef DartOnAudioFrame = void Function(Pointer<AudioFrame> frame);

typedef NativeOnLog = Void Function(Int32 level, Pointer<Utf8> message);
typedef DartOnLog = void Function(int level, Pointer<Utf8> message);

// --- Function Signatures ---

typedef NativeFfmpegInit = Void Function();
typedef DartFfmpegInit = void Function();

typedef NativeFfmpegRelease = Void Function();
typedef DartFfmpegRelease = void Function();

typedef NativeFfmpegOpenMedia = Int32 Function(Pointer<Utf8> url);
typedef DartFfmpegOpenMedia = int Function(Pointer<Utf8> url);

typedef NativeFfmpegGetMediaInfo = MediaInfo Function();
typedef DartFfmpegGetMediaInfo = MediaInfo Function();

typedef NativeFfmpegStartDecoding = Int32 Function();
typedef DartFfmpegStartDecoding = int Function();

typedef NativeFfmpegPause = Int32 Function();
typedef DartFfmpegPause = int Function();

typedef NativeFfmpegResume = Int32 Function();
typedef DartFfmpegResume = int Function();

typedef NativeFfmpegStop = Void Function();
typedef DartFfmpegStop = void Function();

typedef NativeFfmpegSeek = Int32 Function(Int64 timestampMs);
typedef DartFfmpegSeek = int Function(int timestampMs);

typedef NativeFfmpegSetCallbacks = Void Function(
    Pointer<NativeFunction<NativeOnVideoFrame>> videoCb,
    Pointer<NativeFunction<NativeOnAudioFrame>> audioCb,
    Pointer<NativeFunction<NativeOnLog>> logCb);
typedef DartFfmpegSetCallbacks = void Function(
    Pointer<NativeFunction<NativeOnVideoFrame>> videoCb,
    Pointer<NativeFunction<NativeOnAudioFrame>> audioCb,
    Pointer<NativeFunction<NativeOnLog>> logCb);

// --- Bindings Class ---

class LotterwiseFfmpegBindings {
  late final DynamicLibrary _dylib;

  late final DartFfmpegInit init;
  late final DartFfmpegRelease release;
  late final DartFfmpegOpenMedia openMedia;
  late final DartFfmpegGetMediaInfo getMediaInfo;
  late final DartFfmpegStartDecoding startDecoding;
  late final DartFfmpegPause pause;
  late final DartFfmpegResume resume;
  late final DartFfmpegStop stop;
  late final DartFfmpegSeek seek;
  late final DartFfmpegSetCallbacks setCallbacks;

  LotterwiseFfmpegBindings() {
    _dylib = _loadDynamicLibrary();

    init = _dylib.lookupFunction<NativeFfmpegInit, DartFfmpegInit>('ffmpeg_init');
    release = _dylib.lookupFunction<NativeFfmpegRelease, DartFfmpegRelease>('ffmpeg_release');
    openMedia = _dylib.lookupFunction<NativeFfmpegOpenMedia, DartFfmpegOpenMedia>('ffmpeg_open_media');
    getMediaInfo = _dylib.lookupFunction<NativeFfmpegGetMediaInfo, DartFfmpegGetMediaInfo>('ffmpeg_get_media_info');
    startDecoding = _dylib.lookupFunction<NativeFfmpegStartDecoding, DartFfmpegStartDecoding>('ffmpeg_start_decoding');
    pause = _dylib.lookupFunction<NativeFfmpegPause, DartFfmpegPause>('ffmpeg_pause');
    resume = _dylib.lookupFunction<NativeFfmpegResume, DartFfmpegResume>('ffmpeg_resume');
    stop = _dylib.lookupFunction<NativeFfmpegStop, DartFfmpegStop>('ffmpeg_stop');
    seek = _dylib.lookupFunction<NativeFfmpegSeek, DartFfmpegSeek>('ffmpeg_seek');
    setCallbacks = _dylib.lookupFunction<NativeFfmpegSetCallbacks, DartFfmpegSetCallbacks>('ffmpeg_set_callbacks');
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
