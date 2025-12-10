class MediaInfo {
  final Duration duration;
  final int width;
  final int height;
  final double fps;
  final int audioSampleRate;
  final int audioChannels;

  MediaInfo({
    required this.duration,
    required this.width,
    required this.height,
    required this.fps,
    required this.audioSampleRate,
    required this.audioChannels,
  });

  @override
  String toString() {
    return 'MediaInfo(duration: $duration, video: ${width}x$height @ $fps fps, audio: $audioChannels ch @ $audioSampleRate Hz)';
  }
}
