import 'dart:typed_data';

class VideoFrame {
  final Uint8List rgbaBytes;
  final int width;
  final int height;
  final Duration pts;

  VideoFrame({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.pts,
  });
}

class AudioFrame {
  final Float32List samples;
  final int sampleRate;
  final int channels;
  final Duration pts;

  AudioFrame({
    required this.samples,
    required this.sampleRate,
    required this.channels,
    required this.pts,
  });
}
