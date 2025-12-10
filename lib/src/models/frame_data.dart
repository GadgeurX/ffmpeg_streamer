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
