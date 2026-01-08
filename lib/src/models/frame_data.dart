import 'dart:typed_data';

/// Represents a single decoded video frame.
class VideoFrame {
  /// The raw RGBA bytes of the frame.
  final Uint8List rgbaBytes;

  /// The width of the frame in pixels.
  final int width;

  /// The height of the frame in pixels.
  final int height;

  /// The presentation timestamp of the frame.
  final Duration pts;

  /// The frame ID (derived from timestamp and FPS).
  final int frameId;

  VideoFrame({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.pts,
    required this.frameId,
  });
}

/// Represents a single decoded audio frame.
class AudioFrame {
  /// The raw audio samples (typically 32-bit float).
  final Float32List samples;

  /// The sample rate of the audio in Hertz.
  final int sampleRate;

  /// The number of audio channels.
  final int channels;

  /// The presentation timestamp of the frame.
  final Duration pts;

  AudioFrame({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.pts,
  });
}

/// Represents a complete media frame containing both video and audio data.
class MediaFrame {
  /// The video data of this frame, if available.
  final VideoFrame? video;

  /// The audio data of this frame, if available.
  final AudioFrame? audio;

  /// The presentation timestamp of this frame.
  Duration get pts {
    return video?.pts ?? audio?.pts ?? Duration.zero;
  }

  /// The frame ID.
  int get frameId {
    return video?.frameId ?? 0;
  }

  /// Whether this frame contains video data.
  bool get hasVideo => video != null;

  /// Whether this frame contains audio data.
  bool get hasAudio => audio != null;

  MediaFrame({
    this.video,
    this.audio,
  });

  /// Creates a MediaFrame with only video data.
  MediaFrame.withVideo(this.video) : audio = null;

  /// Creates a MediaFrame with only audio data.
  MediaFrame.withAudio(this.audio) : video = null;

  /// Creates a MediaFrame with both video and audio data.
  MediaFrame.withBoth(this.video, this.audio);

  /// Returns video-only frame using the existing video data.
  VideoFrame? toVideoFrame() => video;

  /// Returns audio-only frame using the existing audio data.
  AudioFrame? toAudioFrame() => audio;
}
